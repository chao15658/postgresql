--官方例子
CREATE OR REPLACE FUNCTION get_film_titles(p_year INTEGER)
   RETURNS text AS $$
DECLARE 
 titles TEXT DEFAULT '';
 rec_film   RECORD;
 cur_films CURSOR(p_year INTEGER) FOR SELECT * FROM film WHERE release_year = p_year;
BEGIN
   -- 打开游标
   OPEN cur_films(p_year);
 
   LOOP
    -- 获取记录放入film
      FETCH cur_films INTO rec_film;
    -- exit when no more row to fetch
      EXIT WHEN NOT FOUND;
 
    -- 构建输出
      IF rec_film.title LIKE '%ful%' THEN 
         titles := titles || ',' || rec_film.title || ':' || rec_film.release_year;
      END IF;
   END LOOP;
  
   -- 关闭游标
   CLOSE cur_films;
 
   RETURN titles;
END; $$
 
LANGUAGE plpgsql;

SELECT get_film_titles(2006);

-- 临时表返回结果
BEGIN;
DO $$
    DECLARE
        temp_geometry st_geometry;  
        geometry_record RECORD;
        cur_geometry CURSOR FOR SELECT shape as shape FROM mainbasin;
    BEGIN
        OPEN cur_geometry;
        FETCH cur_geometry INTO temp_geometry;
        LOOP
            FETCH cur_geometry INTO geometry_record;
            EXIT WHEN NOT FOUND;
            temp_geometry := st_union(temp_geometry,geometry_record.shape);
        END LOOP;
        CLOSE cur_geometry;

        DROP TABLE IF EXISTS temp_table;
        CREATE TEMP TABLE temp_table AS 
        SELECT st_envelope(temp_geometry) shape;
    END; 
$$;
COMMIT;
SELECT st_astext(shape) FROM temp_table;


-- 函数返回结果
CREATE OR REPLACE FUNCTION get_basin_data(code varchar,section_shape geometry)
RETURNS VOID AS $$
DECLARE
    record RECORD;
    cur_basin CURSOR(code varchar,section_shape geometry) FOR SELECT objectid,shape FROM sde.main_basin;
BEGIN
    OPEN cur_basin(code,section_shape);
    LOOP
        FETCH cur_basin INTO record;
        EXIT WHEN NOT FOUND;
        --插入数据
        IF st_intersects(section_shape,record.shape) THEN
             INSERT INTO public.table(code, id) VALUES (code, record.objectid);
        END IF;
    END LOOP;
    CLOSE cur_basin;
END; $$
LANGUAGE plpgsql;
