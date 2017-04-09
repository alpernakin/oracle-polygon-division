------------------------------------------------------------------------------------------------------------------------------------
-- Alper Necati Akin
------------------------------------------------------------------------------------------------------------------------------------
-- Polygon division by using oracle spatial. It has been developed for one of Turk Telekom GIS projects by me.
-- Oracle spatial does not have any function or method dividing polygons into two parts. 
-- There is also not a third party library doing this task.
-- Therefore, this code has been written to contribute developers. A geometric algorithm has been developed.
------------------------------------------------------------------------------------------------------------------------------------
-- In total 3 functions, a type, a table and an index have been included. The main function is "divide_polygon_into2" function. 
-- Other functions are coded to help the main function. Their functionalities will be given in the comment sections.
------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------------------------------------
-- drawn_area_temp table is required to run spatial operations such "sdo_relate" with indexed "geoloc" field.
-- See below please to understand the purpose of the table.
------------------------------------------------------------------------------------------------------------------------------------
create table drawn_area_temp(
	id raw(16),
	geoloc mdsys.sdo_geometry,
	constraint drawn_area_temp_pk PRIMARY KEY (id)
);

create index drawn_area_temp_geo_index on drawn_area_temp (geoloc)
	indextype is mdsys.spatial_index;

------------------------------------------------------------------------------------------------------------------------------------
-- This type is defined to store mdsys.sdo_geometry type of data in arrays.
------------------------------------------------------------------------------------------------------------------------------------

create or replace type geom_array is table of mdsys.sdo_geometry;

------------------------------------------------------------------------------------------------------------------------------------
-- This function splits each line of a polygon and returns these lines in an array.

-- Params: 
-- p_polygon: polygon to be divided

-- Return: splitted lines in an array.
------------------------------------------------------------------------------------------------------------------------------------

create or replace function split_polygon_to_lines(p_polygon in mdsys.sdo_geometry)
  return geom_array is

  v_ordinatesIndex number;
  v_linesIndex     number;

  v_lines    	   geom_array := geom_array();
begin
  -- If the parameter is not a polygon, then raise an application error
  if p_polygon.sdo_ordinates.count < 5 then
    raise_application_error(-20009,
                            'The parameter must be polygon type.');
  end if;

  -- It iterates each point of the polygon and distingushes lines one by one.
  for v_ordinatesIndex in 1 .. p_polygon.sdo_ordinates.count - 3 loop
    if mod(v_ordinatesIndex, 2) = 1 then
      v_lines.extend(1);
      v_lines(v_linesIndex) := mdsys.sdo_geometry(2002,
                                                  8307,
                                                  null,
                                                  mdsys.sdo_elem_info_array(1,
                                                                            2,
                                                                            1),
                                                  mdsys.sdo_ordinate_array(p_polygon.sdo_ordinates(v_ordinatesIndex),
                                                                           p_polygon.sdo_ordinates(v_ordinatesIndex + 1),
                                                                           p_polygon.sdo_ordinates(v_ordinatesIndex + 2),
                                                                           p_polygon.sdo_ordinates(v_ordinatesIndex + 3)));

      v_linesIndex := v_linesIndex + 1;
    end if;
  end loop;

  return v_lines;
end;

------------------------------------------------------------------------------------------------------------------------------------
-- This function finds intersecting lines of the polygon with the dividing line.

-- Params: 
-- p_lines: splitted lines of the polygon in an array.
-- p_intersectionPoint: one of intersecting points of the polygon with the dividing line.

-- Return: index of the line which intersects with the point. if there is no line intersects, it returns -1
------------------------------------------------------------------------------------------------------------------------------------

create or replace function find_intersected_line_by_point(p_lines             geom_array,
                                                          p_intersectionPoint mdsys.sdo_geometry)
  return number is
  
  v_guid	      raw(16);
  v_index         number;
  v_isIntersected varchar2(5);
  v_result        number := -1;

  pragma autonomous_transaction;
begin
  -- a guid data is created in order to distinguish p_intersectionPoint in the table.
  v_guid = sys_guid();

  -- drawn_area_temp table is required to be created to run operations like 'sdo_relate'
  -- 'sdo_relate' method reqiures indexed geolocation for matching operations.
  
  -- Therefore, p_intersectionPoint is inserted into drawn_area_temp table to determine ->
  -- if any interaction exists between lines and the point by using sdo_relate  
  insert into drawn_area_temp
    (id, geoloc)
  values
    (v_guid, p_intersectionPoint);
  commit;

  -- sdo_relate operation is used for each line to understand if there is any ineteract.
  for v_index in 1 .. p_lines.count loop
    select sdo_relate(t.geoloc, p_lines(v_index), 'mask=anyinteract')
      into v_isIntersected
      from drawn_area_temp t
     where t.id = v_guid;
  
	-- If current line ineteracts with the point, then set result to index and break loop.
    if v_isIntersected = 'TRUE' then
      v_result := v_index;
      exit;
    end if;
  end loop;

  -- Inserted point is deleted after operation.
  delete drawn_area_temp t
   where t.id = v_guid;
  commit;

  return v_result;
end;

------------------------------------------------------------------------------------------------------------------------------------
-- The main function receives a polygon and a polyline. Polyline divides the polygon into 2 parts.

-- Params:
-- p_polygon: polygon to be divided.
-- p_polyLine: dividing line

-- Return: geom_array type of array that includes two polygons complementing p_polygon.
------------------------------------------------------------------------------------------------------------------------------------

create or replace function divide_polygon_into2(p_polygon  in mdsys.sdo_geometry,
                                                p_polyLine in mdsys.sdo_geometry)
  return geom_array is

  -- counters for points of the polygon
  v_index          number;
  v_ordinatesIndex number;

  -- Index of the first line of the polygon intersecting with dividing line
  v_startIndex number; 
  -- Index of the last line of the polygon intersecting with dividing line
  v_endIndex   number;

  -- A part of the dividing line that takes place in the polygon
  v_intersectedLine       mdsys.sdo_geometry; 
  -- The first point on polygon that intersects with the dividing line  
  v_insersectedFirstPoint mdsys.sdo_geometry; 
  -- The last point on polygon that intersects with the dividing line  
  v_intersectedSecPoint   mdsys.sdo_geometry;

  -- Sub polygon that is extracted from the polygon and added to result array.
  v_polygon      mdsys.sdo_geometry; 
  -- Splitted lines of the polygon in an array.
  v_polygonLines geom_array := geom_array(); 

  -- Return an array of sub polygons
  v_result geom_array := geom_array(); 
begin
  -- A part of the dividing line that intersects with the polygon is determined
  select sdo_geom.sdo_intersection(p_polygon, p_polyLine, 0.005)
    into v_intersectedLine
    from dual;

  -- If the dividing line does not intersect with the polygon or it is not a proper line, then raise an application error
  if v_intersectedLine is null or
     v_intersectedLine.sdo_ordinates.count <= 2 then
    raise_application_error(-20010, 'Drawing failed');
  end if;

  -- One of sub polygons is instanced.
  v_polygon := mdsys.sdo_geometry(2003,
                                  8307,
                                  null,
                                  mdsys.sdo_elem_info_array(1, 1003, 1),
                                  v_intersectedLine.sdo_ordinates);

  -- Splitted lines of the the polygon
  v_polygonLines := split_polygon_to_lines(p_polygon);

  v_ordinatesIndex := v_polygon.sdo_ordinates.count;

  -- First and last intersecting lines of the polygon are determined.
  v_insersectedFirstPoint := mdsys.sdo_geometry(2001,
                                                8307,
                                                mdsys.sdo_point_type(v_polygon.sdo_ordinates(1),
                                                                     v_polygon.sdo_ordinates(2),
                                                                     null),
                                                null,
                                                null);
  v_intersectedSecPoint   := mdsys.sdo_geometry(2001,
                                                8307,
                                                mdsys.sdo_point_type(v_polygon.sdo_ordinates(v_ordinatesIndex - 1),
                                                                     v_polygon.sdo_ordinates(v_ordinatesIndex),
                                                                     null),
                                                null,
                                                null);

  v_startIndex := find_intersected_line_by_point(v_polygonLines,
                                                 v_intersectedSecPoint);
  v_endIndex   := find_intersected_line_by_point(v_polygonLines,
                                                 v_insersectedFirstPoint);

  -- Cycling around polygon from the last intersecting point to last intersecting point
  v_index := v_startIndex;
  if v_startIndex <> v_endIndex then
    loop
      v_polygon.sdo_ordinates.extend(1);
      v_ordinatesIndex := v_ordinatesIndex + 1;
      v_polygon.sdo_ordinates(v_ordinatesIndex) := v_polygonLines(v_index)
                                                   .sdo_ordinates(3);
    
      v_polygon.sdo_ordinates.extend(1);
      v_ordinatesIndex := v_ordinatesIndex + 1;
      v_polygon.sdo_ordinates(v_ordinatesIndex) := v_polygonLines(v_index)
                                                   .sdo_ordinates(4);
    
      if v_index <> v_polygonLines.count then
        v_index := v_index + 1;
      else
        v_index := 1;
      end if;
      exit when v_index = v_endIndex;
    end loop;
  end if;

  -- First latitude and longitude values are added to complete the polygon.
  v_polygon.sdo_ordinates.extend(1);
  v_ordinatesIndex := v_ordinatesIndex + 1;
  v_polygon.sdo_ordinates(v_ordinatesIndex) := v_polygon.sdo_ordinates(1);

  v_polygon.sdo_ordinates.extend(1);
  v_ordinatesIndex := v_ordinatesIndex + 1;
  v_polygon.sdo_ordinates(v_ordinatesIndex) := v_polygon.sdo_ordinates(2);

  -- The first divided polygon was obtained and the second one is obtained by using difference method.
  v_result.extend(1);
  v_result(1) := v_polygon;

  v_result.extend(1);
  v_result(2) := sdo_geom.sdo_difference(p_polygon, v_polygon, 0.005);

  return v_result;
end;
