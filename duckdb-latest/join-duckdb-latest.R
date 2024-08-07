#!/usr/bin/env Rscript

cat("# join-duckdb.R\n")

source("./_helpers/helpers.R")

suppressPackageStartupMessages({
  library("DBI", lib.loc="./duckdb-latest/r-duckdb-latest", warn.conflicts=FALSE)
  library("duckdb", lib.loc="./duckdb-latest/r-duckdb-latest", warn.conflicts=FALSE)
})
ver = packageVersion("duckdb")
#git = "" # set up later on after connecting to db
task = "join"
solution = "duckdb-latest"
cache = TRUE

data_name = Sys.getenv("SRC_DATANAME")
src_jn_x = file.path("data", paste(data_name, "csv", sep="."))
y_data_name = join_to_tbls(data_name)
src_jn_y = setNames(file.path("data", paste(y_data_name, "csv", sep=".")), names(y_data_name))
stopifnot(length(src_jn_y)==3L)
cat(sprintf("loading datasets %s\n", paste(c(data_name, y_data_name), collapse=", ")))

attach_and_use <- function(con, db_file, db) {
  if (on_disk) {
    # in case a previous solution failed during query execution and left the file around.
    if (file.exists(db_file)) {
      unlink(db_file)
    }
    dbExecute(con, sprintf("ATTACH '%s'", db_file))
  } else {
    dbExecute(con, sprintf("CREATE SCHEMA %s", db))
  }
}

detach_and_drop <- function(con, db_file, db) {
  if (on_disk) {
    dbExecute(con, sprintf("DETACH %s", db))
    unlink(db_file)
  } else {
    dbExecute(con, sprintf("DROP SCHEMA %s CASCADE", db))
  }
}

duckdb_join_db = sprintf('%s_%s_%s.db', gsub("-","_",solution), task, data_name)
if (file.exists(duckdb_join_db)) {
  unlink(duckdb_join_db)
}

on_disk = as.numeric(strsplit(data_name, "_", fixed=TRUE)[[1L]][2L])>=1e9
less_cores = as.numeric(strsplit(data_name, "_", fixed=TRUE)[[1L]][2L])<=1e7

uses_NAs = as.numeric(strsplit(data_name, "_", fixed=TRUE)[[1L]][4L])>0

if (on_disk) {
  print("using disk memory-mapped data storage")
  con = dbConnect(duckdb::duckdb(), dbdir=duckdb_join_db)
} else {
  print("using in-memory data storage")
  con = dbConnect(duckdb::duckdb())
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

clean_schema_name <- sprintf("%s_%s_clean.", gsub("-","_",solution), data_name)
clean_db_name <- paste(clean_schema_name, "db", sep="")

if (file.exists(clean_db_name)) {
  unlink(clean_db_name)
}

if (!uses_NAs) {
  if (on_disk) {
    unlink(clean_db_name)
    invisible(dbExecute(con, sprintf("attach '%s'", clean_db_name)))
    db_name = clean_schema_name
  }
  else {
    db_name = ""
  }

  id4_enum_statement = "SELECT id4 FROM x_csv UNION ALL SELECT id4 FROM small_csv UNION ALL SELECT id4 from medium_csv UNION ALL SELECT id4 from big_csv"
  id5_enum_statement = "SELECT id5 FROM x_csv UNION ALL SELECT id5 from medium_csv UNION ALL SELECT id5 from big_csv"
  invisible(dbExecute(con, sprintf("CREATE TYPE id4ENUM AS ENUM (%s)", id4_enum_statement)))
  invisible(dbExecute(con, sprintf("CREATE TYPE id5ENUM AS ENUM (%s)", id5_enum_statement)))

  invisible(dbExecute(con, sprintf("CREATE TABLE %ssmall(id1 INT64, id4 id4ENUM, v2 DOUBLE)", db_name)))
  invisible(dbExecute(con, sprintf("INSERT INTO %ssmall (SELECT * from small_csv)", db_name)))

  invisible(dbExecute(con, sprintf("CREATE TABLE %smedium(id1 INT64, id2 INT64, id4 id4ENUM, id5 id5ENUM, v2 DOUBLE)", db_name)))
  invisible(dbExecute(con, sprintf("INSERT INTO %smedium (SELECT * FROM medium_csv)", db_name)))

  invisible(dbExecute(con, sprintf("CREATE TABLE %sbig(id1 INT64, id2 INT64, id3 INT64, id4 id4ENUM, id5 id5ENUM, id6 VARCHAR, v2 DOUBLE)", db_name)))
  invisible(dbExecute(con, sprintf("INSERT INTO %sbig (Select * from big_csv)", db_name)))

  invisible(dbExecute(con, sprintf("CREATE TABLE %sx(id1 INT64, id2 INT64, id3 INT64, id4 id4ENUM, id5 id5ENUM, id6 VARCHAR, v1 DOUBLE)", db_name)))
  invisible(dbExecute(con, sprintf("INSERT INTO %sx (SELECT * FROM x_csv);", db_name)))

  # drop all the csv ingested tables
  invisible({
    dbExecute(con, "DROP TABLE x_csv")
    dbExecute(con, "DROP TABLE small_csv")
    dbExecute(con, "DROP TABLE medium_csv")
    dbExecute(con, "DROP TABLE big_csv")
  })

  if (on_disk) {
    dbDisconnect(con, shutdown=TRUE)
    unlink(duckdb_join_db)
    con <- dbConnect(duckdb(), dbdir=clean_db_name)
  }
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


attach_and_use(con, 'q1.db', 'q1')
t = system.time({
  dbExecute(con, "CREATE TABLE q1.ans AS SELECT x.*, small.id4 AS small_id4, v2 FROM x JOIN small USING (id1)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q1.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q1.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q1.ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
invisible(dbExecute(con, "DROP TABLE IF EXISTS q1.ans"))
detach_and_drop(con, 'q1.db', 'q1')
attach_and_use(con, 'q1.db', 'q1')
t = system.time({
  dbExecute(con, "CREATE TABLE q1.ans AS SELECT x.*, small.id4 AS small_id4, v2 FROM x JOIN small USING (id1)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q1.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q1.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q1.ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
print(dbGetQuery(con, "SELECT * FROM q1.ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM q1.ans WHERE ROWID > (SELECT count(*) FROM q1.ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS q1.ans"))
detach_and_drop(con, 'q1.db', 'q1')

question = "medium inner on int" # q2
fun = "inner_join"


attach_and_use(con, 'q2.db', 'q2')
t = system.time({
  dbExecute(con, "CREATE TABLE q2.ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x JOIN medium USING (id2)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q2.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q2.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q2.ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
invisible(dbExecute(con, "DROP TABLE IF EXISTS q2.ans"))
detach_and_drop(con, 'q2.db', 'q2')
attach_and_use(con, 'q2.db', 'q2')
t = system.time({
  dbExecute(con, "CREATE TABLE q2.ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x JOIN medium USING (id2)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q2.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q2.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q2.ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
print(dbGetQuery(con, "SELECT * FROM q2.ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM q2.ans WHERE ROWID > (SELECT count(*) FROM q2.ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS q2.ans"))
detach_and_drop(con, 'q2.db', 'q2')

question = "medium outer on int" # q3
fun = "left_join"

attach_and_use(con, 'q3.db', 'q3')
t = system.time({
  dbExecute(con, "CREATE TABLE q3.ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x LEFT JOIN medium USING (id2)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q3.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q3.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q3.ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
invisible(dbExecute(con, "DROP TABLE IF EXISTS q3.ans"))
detach_and_drop(con, 'q3.db', 'q3')
attach_and_use(con, 'q3.db', 'q3')
t = system.time({
  dbExecute(con, "CREATE TABLE q3.ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id4 AS medium_id4, medium.id5 AS medium_id5, v2 FROM x LEFT JOIN medium USING (id2)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q3.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q3.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q3.ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
print(dbGetQuery(con, "SELECT * FROM q3.ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM q3.ans WHERE ROWID > (SELECT count(*) FROM q3.ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS q3.ans"))
detach_and_drop(con, 'q3.db', 'q3')

question = "medium inner on factor" # q4
fun = "inner_join"

attach_and_use(con, 'q4.db', 'q4')
t = system.time({
  dbExecute(con, "CREATE TABLE q4.ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id2 AS medium_id2, medium.id4 AS medium_id4, v2 FROM x JOIN medium USING (id5)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q4.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q4.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q4.ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
invisible(dbExecute(con, "DROP TABLE IF EXISTS q4.ans"))
detach_and_drop(con, 'q4.db', 'q4')
attach_and_use(con, 'q4.db', 'q4')
t = system.time({
  dbExecute(con, "CREATE TABLE q4.ans AS SELECT x.*, medium.id1 AS medium_id1, medium.id2 AS medium_id2, medium.id4 AS medium_id4, v2 FROM x JOIN medium USING (id5)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q4.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q4.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q4.ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
print(dbGetQuery(con, "SELECT * FROM q4.ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM q4.ans WHERE ROWID > (SELECT count(*) FROM q4.ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS q4.ans"))
detach_and_drop(con, 'q4.db', 'q4')

question = "big inner on int" # q5
fun = "inner_join"

attach_and_use(con, 'q5.db', 'q5')
t = system.time({
  dbExecute(con, "CREATE TABLE q5.ans AS SELECT x.*, big.id1 AS big_id1, big.id2 AS big_id2, big.id4 AS big_id4, big.id5 AS big_id5, big.id6 AS big_id6, v2 FROM x JOIN big USING (id3)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q5.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q5.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q5.ans"))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
invisible(dbExecute(con, "DROP TABLE IF EXISTS q5.ans"))
detach_and_drop(con, 'q5.db', 'q5')
attach_and_use(con, 'q5.db', 'q5')
t = system.time({
  dbExecute(con, "CREATE TABLE q5.ans AS SELECT x.*, big.id1 AS big_id1, big.id2 AS big_id2, big.id4 AS big_id4, big.id5 AS big_id5, big.id6 AS big_id6, v2 FROM x JOIN big USING (id3)")
  print(c(nr<-dbGetQuery(con, "SELECT count(*) AS cnt FROM q5.ans")$cnt, nc<-ncol(dbGetQuery(con, "SELECT * FROM q5.ans LIMIT 0"))))
})[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-dbGetQuery(con, "SELECT SUM(v1) AS v1, SUM(v2) AS v2 FROM q5.ans"))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=in_nr, question=question, out_rows=nr, out_cols=nc, solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk)
print(dbGetQuery(con, "SELECT * FROM q5.ans LIMIT 3"))                                      ## head
print(dbGetQuery(con, "SELECT * FROM q5.ans WHERE ROWID > (SELECT count(*) FROM q5.ans) - 4")) ## tail
invisible(dbExecute(con, "DROP TABLE IF EXISTS q5.ans"))
detach_and_drop(con, 'q5.db', 'q5')

dbDisconnect(con, shutdown=TRUE)

if (on_disk) {
  unlink(clean_db_name)
}

cat(sprintf("joining finished, took %.0fs\n", proc.time()[["elapsed"]]-task_init))

if( !interactive() ) q("no", status=0)