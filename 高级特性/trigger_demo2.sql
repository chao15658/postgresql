--触发器demo
CREATE TABLE COMPANY(
           ID INT PRIMARY KEY     NOT NULL,
           NAME           TEXT    NOT NULL,
           AGE            INT     NOT NULL,
           ADDRESS        CHAR(50),
           SALARY         REAL
        );
       
CREATE OR REPLACE FUNCTION auditlogfunc() RETURNS TRIGGER AS $example_table$
 BEGIN
     INSERT INTO AUDIT(EMP_ID, ENTRY_DATE) VALUES (new.ID, current_timestamp);
     RETURN NEW;
  END;
$example_table$ LANGUAGE plpgsql;

CREATE TRIGGER example_trigger 
AFTER INSERT ON COMPANY 
FOR EACH ROW 
EXECUTE PROCEDURE auditlogfunc();

