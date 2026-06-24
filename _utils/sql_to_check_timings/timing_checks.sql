-- run this in duckdb

create table timings as select * from read_csv_auto('reports/oct_25/time.csv');


-- check what solutions might have bad out rows
select t1.question, t1.data, t1.out_rows, t1.solution, t2.out_rows, t2.solution from
   timings t1, timings t2 
 where t1.out_rows != t2.out_rows 
 and t1.question = t2.question 
 and t1.solution != 'clickhouse'
 and t2.solution != 'clickhouse'
 and t1.task = t2.task
 -- and t1.task = 'groupby'
 -- and t1.solution != 'arrow'
 -- and t2.solution != 'arrow'
 and t2.solution != 'datafusion'
 and t1.question != 'sum v3 count by id1:id6'
 and t1.data != 'G1_1e8_1e2_5_0'
 and t1.data = t2.data ;


-- Value of 'chk' varies for different runs for single solution+question
create table timings as select * from read_csv('time.csv');

select t1.chk, t2.chk, t1.solution, t2.solution from
   timings t1, timings t2 
 where t1.chk != t2.chk 
 and t1.question = t2.question 
 and t1.task = t2.task
 and t1.solution != 'datafusion'
 and t2.solution != 'datafusion'
 and t1.solution != 'arrow'
 and t2.solution != 'arrow'
 and t1.solution != 'R-arrow'
 and t2.solution != 'R-arrow'
 and t1.solution != 'collapse'
 and t1.solution = t2.solution
 and t1.data = t2.data group by all;


 select t1.question, t1.chk, t2.chk, t1.data, t1.solution, t1.version from
   timings t1, timings t2 
 where t1.chk != t2.chk 
 and t1.question = t2.question 
 and t1.task = t2.task
 and t1.solution = 'duckdb'
 and t2.solution = 'duckdb'
 and t1.version = t2.version
 and t1.version = '1.5.4'
 and t1.data = t2.data group by all;


select t1.question, t1.data, t1.out_rows, t2.solution, t2.out_rows from 
timings t1, timings t2
where t1.out_rows != t2.out_rows
and t1.question = t2.question 
and t1.solution != 'clickhouse'
and t2.solution != 'clickhouse'
and t1.question = 'medium outer on int'
and t1.data = t2.data;


# check result differences
select * from 
(select t1.question, t1.data, string_split(t1.chk, ';')::DOUBLE[] t1_ans, string_split(t2.chk, ';')::DOUBLE[] t2_ans, t1.solution, t1.version, t2.version from
            timings t1, timings t2
          where t1.chk != t2.chk
          and t1.question = t2.question
          and t1.task = t2.task
          and t1.solution = 'duckdb'
          and t2.solution = 'duckdb'
          and t1.version = '1.5.4'
          and t2.version like '%1.0%'
          and t2.version not like '1.0.99.9000'
          and t1.data like 'G1_1e9%'
          and t1.data = t2.data group by all) where abs(t1_ans[1] - t2_ans[1]) > 0.002;