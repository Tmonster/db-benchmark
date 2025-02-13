#!/usr/bin/env Rscript

cat("# join-collapse.R\n")

source("./_helpers/helpers.R")

stopifnot(requireNamespace(c("data.table"), quietly=TRUE)) # used for data loading
.libPaths("./collapse/r-collapse") # tidyverse/collapse#4641
suppressPackageStartupMessages(library("collapse", lib.loc="./collapse/r-collapse", warn.conflicts=FALSE))
ver = packageVersion("collapse")
git = "" # uses stable version now #124
task = "join"
solution = "collapse"
cache = TRUE
on_disk = FALSE

data_name = Sys.getenv("SRC_DATANAME")
machine_type = Sys.getenv("MACHINE_TYPE")
src_jn_x = file.path("data", paste(data_name, "csv", sep="."))
y_data_name = join_to_tbls(data_name)
src_jn_y = setNames(file.path("data", paste(y_data_name, "csv", sep=".")), names(y_data_name))
stopifnot(length(src_jn_y)==3L)
cat(sprintf("loading datasets %s\n", paste(c(data_name, y_data_name), collapse=", ")))

on_disk = (machine_type == "small" && as.numeric(strsplit(data_name, "_", fixed=TRUE)[[1L]][2L])>=1e9)

x = data.table::fread(src_jn_x, showProgress=FALSE, stringsAsFactors=TRUE, data.table=FALSE, na.strings="")
data.table::setDF(x)
JN = lapply(sapply(simplify=FALSE, src_jn_y, data.table::fread, showProgress=FALSE, stringsAsFactors=TRUE, data.table=FALSE, na.strings=""), as.data.frame)
print(nrow(x))
sapply(sapply(JN, nrow), print) -> nul
small = JN$small
medium = JN$medium
big = JN$big

task_init = proc.time()[["elapsed"]]
cat("joining...\n")

question = "small inner on int" # q1
fun = "inner_join"
t = system.time(print(dim(ans<-join(x, small, on="id1", how="inner", verbose=0))))[["elapsed"]]


m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
rm(ans)
t = system.time(print(dim(ans<-join(x, small, on="id1", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(head(ans, 3))
print(tail(ans, 3))
rm(ans)

question = "medium inner on int" # q2
fun = "inner_join"
t = system.time(print(dim(ans<-join(x, medium, on="id2", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
rm(ans)
t = system.time(print(dim(ans<-join(x, medium, on="id2", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(head(ans, 3))
print(tail(ans, 3))
rm(ans)

question = "medium outer on int" # q3
fun = "left_join"
t = system.time(print(dim(ans<-join(x, medium, on="id2", how="left", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
rm(ans)
t = system.time(print(dim(ans<-join(x, medium, on="id2", how="left", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(head(ans, 3))
print(tail(ans, 3))
rm(ans)

question = "medium inner on factor" # q4
fun = "inner_join"
t = system.time(print(dim(ans<-join(x, medium, on="id5", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
rm(ans)
t = system.time(print(dim(ans<-join(x, medium, on="id5", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(head(ans, 3))
print(tail(ans, 3))
rm(ans)

question = "big inner on int" # q5
fun = "inner_join"
t = system.time(print(dim(ans<-join(x, big, on="id3", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=1L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
rm(ans)
t = system.time(print(dim(ans<-join(x, big, on="id3", how="inner", verbose=0))))[["elapsed"]]
m = memory_usage()
chkt = system.time(chk<-fsum(fselect(ans, v1, v2), drop = FALSE))[["elapsed"]]
write.log(run=2L, task=task, data=data_name, in_rows=nrow(x), question=question, out_rows=nrow(ans), out_cols=ncol(ans), solution=solution, version=ver, git=git, fun=fun, time_sec=t, mem_gb=m, cache=cache, chk=make_chk(chk), chk_time_sec=chkt, on_disk=on_disk, machine_type=machine_type)
print(head(ans, 3))
print(tail(ans, 3))
rm(ans)

cat(sprintf("joining finished, took %.0fs\n", proc.time()[["elapsed"]]-task_init))

if( !interactive() ) q("no", status=0)
