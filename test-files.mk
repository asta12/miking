# All relevant source files to include in the tests
src_files_all =\
	$(wildcard stdlib/*.mc)\
	$(wildcard stdlib/**/*.mc)\
	$(wildcard test/mexpr/*.mc)\
	$(wildcard test/mlang/*.mc)\
	$(wildcard test/py/*.mc)


# These programs has special external dependencies which might be tedious to
# install or are mutually exclusive with other dependencies.
sundials_files = $(wildcard stdlib/sundials/*.mc)
ipopt_files = $(wildcard stdlib/ipopt/*.mc)

special_dependencies_files +=\
	$(sundials_files)\
	$(ipopt_files)


# These are special, special cases since the python externals are implemented
# differently from other externals and can therefore not be compiled.
python_files += stdlib/python/python.mc
python_files += $(wildcard test/py/*.mc)


# Programs that we currently cannot compile/test. These are programs written
# before the compiler was implemented. It is forbidden to add to this list of
# programs but removing from it is very welcome.
compile_files_exclude += stdlib/dfa.mc
compile_files_exclude += stdlib/json.mc
compile_files_exclude += stdlib/nfa.mc
compile_files_exclude += stdlib/parser-combinators.mc
compile_files_exclude += stdlib/regex.mc
compile_files_exclude += test/mexpr/nestedpatterns.mc
compile_files_exclude += test/mlang/also_includes_lib.mc
compile_files_exclude += test/mlang/mlang.mc
compile_files_exclude += test/mlang/nestedpatterns.mc
compile_files_exclude += test/mlang/catchall.mc


# Programs that we currently cannot interpret/test. These are programs written
# before the compiler was implemented. It is forbidden to add to this list of
# programs but removing from it is very welcome.
run_files_exclude += stdlib/regex.mc
run_files_exclude += stdlib/parser-combinators.mc
run_files_exclude += test/mlang/catchall.mc
run_files_exclude += test/mlang/mlang.mc


# Programs that we should be able to compile/test if we prune utests.
compile_files_prune =\
	$(filter-out $(python_files) $(compile_files_exclude), $(src_files_all))


# Programs that we should be able to compile/test, even without utest pruning,
# if all, except the special, external dependencies are met.
compile_files =\
	$(filter-out $(special_dependencies_files), $(compile_files_prune))


# Programs the we should be able to interpret/test with the interpreter.
run_files = $(filter-out $(python_files) $(run_files_exclude), $(src_files_all))


# Programs that we should be able to interpret/test with boot.
boot_files = $(filter-out $(python_files), $(src_files_all))