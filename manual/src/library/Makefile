ROOTDIR = ../../..

TEXQUOTE = $(ROOTDIR)/runtime/ocamlrun ../../tools/texquote2
CAMLLATEX = CAML_LD_LIBRARY_PATH="" $(OCAMLRUN) $(addprefix -I ,$(LD_PATH)) \
  $(ROOTDIR)/tools/caml-tex -repo-root $(ROOTDIR) -n 80 -v false

FILES = core.tex builtin.tex stdlib-blurb.tex compilerlibs.tex \
  libunix.tex libstr.tex old.tex libthreads.tex libdynlink.tex \
  libruntime_events.tex

etex-files: $(FILES)
all: etex-files

%.gen.tex: %.etex
	$(CAMLLATEX) $< -o $@

%.tex: %.gen.tex
	$(TEXQUOTE) < $< > $*.texquote_error.tex
	mv $*.texquote_error.tex $@


.PHONY: clean
clean:
	rm -f *.tex ocamldoc.out ocamldoc.sty

.PHONY: distclean
distclean: clean
