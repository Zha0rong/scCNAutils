check:
	Rscript -e 'devtools::check()'

test:
	Rscript -e 'devtools::test()'

manual: docs/scCNAutils-manual.pdf

docs/scCNAutils-manual.pdf: man/*.Rd
	rm -f docs/scCNAutils-manual.pdf
	R CMD Rd2pdf . --no-preview -o docs/scCNAutils-manual.pdf

## install mermaid with 'npm install mermaid.cli'
flowcharts: docs/flowchart-cnasignal.png

docs/flowchart-cnasignal.png: docs/flowchart-cnasignal.mmd
	./node_modules/.bin/mmdc -w 1000 -i docs/flowchart-cnasignal.mmd -o docs/flowchart-cnasignal.png

