
all: package.ps nst.ps test.ps check.ps
	#

%.ps: %.lisp
	enscript -2r --lines-per-page=57 -o $@ $<

clean:
	rm -f *.fasl *.ps
