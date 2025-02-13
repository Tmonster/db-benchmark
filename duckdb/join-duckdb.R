#!/usr/bin/env Rscript

cat("# join-duckdb.R\n")

source("./_helpers/helpers.R")

suppressPackageStartupMessages({
  library("DBI", lib.loc="./duckdb/r-duckdb", warn.conflicts=FALSE)
  library("duckdb", lib.loc="./duckdb/r-duckdb", warn.conflicts=FALSE)
})
ver = packageVersion("duckdb")
#git = "" # set up later on after connecting to db
task = "join"
solution = "duckdb"
cache = TRUE

data_name = Sys.getenv("SRC_DATANAME")
machine_type = Sys.getenv("MACHINE_TYPE")
src_jn_x = file.path("data", paste(data_name, "csv", sep="."))
y_data_name = join_to_tbls(data_name)
src_jn_y = setNames(file.path("data", paste(y_data_name, "csv", sep=".")), names(y_data_name))
stopifnot(length(src_jn_y)==3L)
cat(sprintf("loading datasets %s\n", paste(c(data_name, y_data_name), collapse=", ")))

duckdb_join_db = sprintf('%s_%s_%s.db', solution, task, data_name)
on_disk = as.numeric(strsplit(data_name, "_", fixed=TRUE)[[1L]][2L])>=1e9

less_cores = as.numeric(strsplit("J1_1e7_NA_0_0", "_", fixed=TRUE)[[1L]][2L])<=1e7

uses_NAs = as.numeric(strsplit(data_name, "_", fixed=TRUE)[[1L]][4L])>0

if (on_disk) {
  print("using disk memory-mapped data storage")
  con = dbConnect(duckdb::duckdb(), dbdir=duckdb_join_db)
} else {
  print("using in-memory data storage")
  con = dbConnect(duckdb::duckdb())
}

if (machine_type == 'c6id.4xlarge') {
  dbExecute(con, "pragma memory_limit='25G'")
}

ncores = parallel::detectCores()
if (less_cores) {
  ncores = min(ncores, 40)
}

invisible(dbExecute(con, sprintf("PRAGMA THREADS=%d", ncores)))
git = dbGetQuery(con, "SELECT source_id FROM pragma_version()")[[1L]]

invisible({
  dbExecute(con, sprintf("CREATE TABLE x_csv AS SELECT * FROM read_csv_auto('%s')", src_jn_x))
  dbExecute(con, sprintf("CREATE TABLE small_csv AS SELECT * FROM read_csv_auto('%s')", src_jn_y[1L]))
  dbExecute(con, sprintf("CREATE TABLE medium_csv AS SELECT * FROM read_csv_auto('%s')", src_jn_y[2L]))
  dbExecute(con, sprintf("CREATE TABLE big_csv AS SELECT * FROM read_csv_auto('%s')", src_jn_y[3L]))
})

if (!uses_NAs) {

  id4_enum_statement = "SELECT id4 FROM x_csv UNION ALL SELECT id4 FROM small_csv UNION ALL SELECT id4 from medium_csv UNION ALL SELECT id4 from big_csv"
  id5_enum_statement = "SELECT id5 FROM x_csv UNION ALL SELECT id5 from medium_csv UNION ALL SELECT id5 from big_csv"
  invisible(dbExecute(con, sprintf("CREATE TYPE id4ENUM AS ENUM (%s)", id4_enum_statement)))
  invisible(dbExecute(con, sprintf("CREATE TYPE id5ENUM AS ENUM (%s)", id5_enum_statement)))

  invisible(dbExecute(con, "CREATE TABLE small(id1 INT64, id4 id4ENUM, v2 DOUBLE)"))
  invisible(dbExecute(con, "INSERT INTO small (SELECT * from small_csv)"))

  invisible(dbExecute(con, "CREATE TABLE medium(id1 INT64, id2 INT64, id4 id4ENUM, id5 id5ENUM, v2 DOUBLE)"))
  invisible(dbExecute(con, "INSERT INTO medium (SELECT * FROM medium_csv)"))

  invisible(dbExecute(con, "CREATE TABLE big(id1 INT64, id2 INT64, id3 INT64, id4 id4ENUM, id5 id5ENUM, id6 VARCHAR, v2 DOUBLE)"))
  invisible(dbExecute(con, "INSERT INTO big (Select * from big_csv)"))

  invisible(dbExecute(con, "CREATE TABLE x(id1 INT64, id2 INT64, id3 INT64, id4 id4ENUM, id5 id5ENUM, id6 VARCHAR, v1 DOUBLE)"))
  invisible(dbExecute(con, "INSERT INTO x (SELECT * FROM x_csv);"))

  # drop all the csv ingested tables
  invisible({
    dbExecute(con, "DROP TABLE x_csv")
    dbExecute(con, "DROP TABLE small_csv")
    dbExecute(con, "DROP TABLE medium_csv")
    dbExecute(con, "DROP TABLE big_csv")
  })
} else {
  invisible({
    dbExecute(con, "ALTER TABLE x_csv RENAME TO x")
    dbExecute(con, "ALTER TABLE small_csv RENAME TO small")
    dbExecute(con, "ALTER TABLE medium_csv RENAME TO medium")
    dbExecute(con, "ALTER TABLE big_csv RENAME TO big")
  })
}

print(in_nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM x")$cnt)
print(dbGetQuery(con, "SELECT count(*) AS cnt FROM small")$cnt)
print(dbGetQuery(con, "SELECT count(*) AS cnt FROM medium")$cnt)
print(dbGetQuery(con, "SELECT count(*) AS cnt FROM big")$cnt)

task_init = proc.time()[["elapsed"]]
cat("joining...\n")

question = "small inner on int" # q1
fun = "inner_join"


table_type = "TEMP"
if (on_disk) {
  dbExecute(con, "pragma memory_limit='25G'")
  table_type = ""
}

t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, small.id4 AS small_id4, v2 FROM x JOIN small USING (id1)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))
t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, small.id4 AS small_id4, v2 FROM x JOIN small USING (id1)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(dbGetQuery(con, "SELECT * FROM ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM ans WHERE ROWID > (SELECT count(*) FROM ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))

question = "medium inner on int" # q2
fun = "inner_join"


t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x JOIN medium USING (id2)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))
t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x JOIN medium USING (id2)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(dbGetQuery(con, "SELECT * FROM ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM ans WHERE ROWID > (SELECT count(*) FROM ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))

question = "medium outer on int" # q3
fun = "left_join"

t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x LEFT JOIN medium USING (id2)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))
t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x LEFT JOIN medium USING (id2)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(dbGetQuery(con, "SELECT * FROM ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM ans WHERE ROWID > (SELECT count(*) FROM ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))

question = "medium inner on factor" # q4
fun = "inner_join"

t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id2 AS medium_id2, medium.id4 AS medium_id4, v2 FROM x JOIN medium USING (id5)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))
t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id2 AS medium_id2, medium.id4 AS medium_id4, v2 FROM x JOIN medium USING (id5)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(dbGetQuery(con, "SELECT * FROM ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM ans WHERE ROWID > (SELECT count(*) FROM ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))

question = "big inner on int" # q5
fun = "inner_join"

t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, big.id1 AS big_id1, big.id2 AS big_id2, big.id4 AS big_id4, big.id5 AS big_id5, big.id6 AS big_id6, v2 FROM x JOIN big USING (id3)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))
t = system.time({
  dbExecute(con, sprintf("CREATE %s TABLE ans AS SELECT x.*, big.id1 AS big_id1, big.id2 AS big_id2, big.id4 AS big_id4, big.id5 AS big_id5, big.id6 AS big_id6, v2 FROM x JOIN big USING (id3)", table_type))
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(dbGetQuery(con, "SELECT * FROM ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM ans WHERE ROWID > (SELECT count(*) FROM ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS ans"))

dbDisconnect(con, shutdown=TRUE)

cat(sprintf("joining finished, took %.0fs\n", proc.time()[["elapsed"]]-task_init))

if( !interactive() ) q("no", status=0)
