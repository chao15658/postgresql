CREATE OR REPLACE
FUNCTION dzys_user_inter_insert_fun()
RETURNS trigger
LANGUAGE plpgsql
AS
$function$
BEGIN
if Tri_dzys_user_insrt = 1 then
   insert into dzys_user_inter(Tri_Mode,USER_ID,CUST_ID,REGION_CODE,USER_REGION,
       USER_PASSWORD,USER_NUMBER,PrePay_TAG,FIRST_CALL_TIME,CREATE_TIME,OPEN_TIME,
       REMOVE_TAG,Destory_Time,work_time,REMARK)
   VALUES('AFTER INSERT',new.USER_ID,new.CUST_ID,new.REGION_CODE,new.USER_REGION,
       new.USER_PASSWORD,new.USER_NUMBER,new.PrePay_TAG,new.FIRST_CALL_TIME,new.CREATE_TIME,new.OPEN_TIME,
       new.REMOVE_TAG,new.Destory_Time,new.work_time,new.REMARK);
end if;
RETURN NEW;
END;
$function$;
-- 插入数据的触发器，启用需要set@Tri_dzys_user_insrt = 1

CREATE TRIGGER Tri_dzys_user_insrt
  AFTER INSERT ON dzys_user
  FOR EACH ROW
EXECUTE PROCEDURE  dzys_user_inter_insert_fun()



--启用触发器
alter table dbtest.dzys_user enable trigger dzys_user_inter;

--禁用触发器
alter table dbtest.dzys_user disable trigger dzys_user_inter;
  
  