##' Computes information at the gene level that can be used to annotate
##' the results later (e.g. CNA calls).
##'
##' If the input data.frame has a symbol column, 'genes_coord' is used to
##' add the coordinates, later used to overlap with region/CNA calls. If
##' the input data.frame has coordinates, 'genes_coord' is used to retrieve
##' the gene name. In both cases a row in the input data.frame must be a
##' gene, not a bin.
##'
##' It's better to run this function after normalization (\code{norm_ge}
##' but before binning (\code{bin_genes}).
##' @title Gene information
##' @param ge_df a data.frame with gene expression
##' information across cells. E.g. after \code{norm.ge}.
##' @param genes_coord either a file name or a data.frame with coordinates
##' and gene names.
##' @param subset_cells the maximum number of cells to use.
##' @return a data.frame with summary stats for each gene.
##' @author Jean Monlong
##' @export
gene_info <- function(ge_df, genes_coord, subset_cells=1e4){
  if(!all(c('chr','start','end') %in% colnames(ge_df)) &
     !('symbol' %in% colnames(ge_df))){
    stop('"ge_df" must have either a column "symbol", or coordinates columns chr/start/end.')
  }

  if(!is.data.frame(genes_coord)){
    if(is.character(genes_coord) & length(genes_coord) == 1){
      genes_coord = utils::read.table(genes_coord, as.is=TRUE, header=TRUE)
    } else {
      stop('genes_coord must be either a file name or a data.frame.')
    }
  }

  ge.info = ge_df[, intersect(colnames(ge_df), c('symbol', 'chr', 'start', 'end'))]
  cells = setdiff(colnames(ge_df), c('symbol', 'chr', 'start', 'end'))

  ## Subset cells
  if(!is.null(subset_cells) && length(cells)>subset_cells){
    cells = sample(cells, subset_cells)
  }
  
  ## Compute gene-level metrics
  ge.info$exp.mean = apply(as.matrix(ge_df[, cells]), 1, mean, na.rm=TRUE)
  ge.info$exp.sd = apply(as.matrix(ge_df[, cells]), 1, stats::sd, na.rm=TRUE)
  ge.info$prop.non0 = apply(as.matrix(ge_df[, cells]), 1, function(x) mean(x>0, na.rm=TRUE))

  ## Merge with gene names/coords
  if(!all(c('symbol', 'chr','start','end') %in% colnames(ge_df))){
    ge.info = merge(ge.info, genes_coord)
  }

  return(ge.info)
}
