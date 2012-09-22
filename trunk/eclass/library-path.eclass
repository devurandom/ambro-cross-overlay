# @ECLASS: library-path.eclass

# @FUNCTION: library-path-run
# @DESCRIPTION:
# Run a program with modified environment such that the system will first look for shared
# libraries in the directory specified by the first argument. Multiple directories
# can be specified by separating then with colons.
library-path-run() {
	local extra=$1
	shift
	if [[ ${CHOST} != *-darwin* ]]; then
		LD_LIBRARY_PATH="${extra}:${LD_LIBRARY_PATH}" "$@"
	else
		DYLD_LIBRARY_PATH="${extra}:${DYLD_LIBRARY_PATH}" "$@"
	fi
}
