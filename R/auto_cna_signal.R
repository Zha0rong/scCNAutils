##' Goes from reading raw gene counts to CNA-level signal, tSNE and community detection.
##' @title Automated pipeline to compute CNA signal from scRNA expression
##' @param data a data.frame with gene expression or the path to the folder with the
##' 'matrix.mtx', 'genes.tsv' and 'barcodes.tsv' files. A list if multiple samples.
##' @param genes_coord either a file name or a data.frame with coordinates
##' and gene names.
##' @param prefix the prefix to use for the files created by this function (e.g. graphs).
##' @param nb_cores the number of processors to use.
##' @param pause_after_qc pause after the QC to pick custom QC thresholds.
##' @param use_cache should intermediate files used and avoid redoing steps?
##' @param sample_names the names of each sample. If NULL, tries to use data's names.
##' @param info_df a data.frame with information about cells.
##' @param max_mito_prop the maximum proportion of mitochondrial RNA.
##' @param min_total_exp the minimum total cell expression
##' @param cells_sel consider only these cells. Other cells filtered no matter what.
##' @param chrs the chromosome names to keep. NULL to include all the chromosomes.
##' @param cell_cycle if non-null, either a file or data.frame to compute cell
##' cycle scores. See details.
##' @param bin_mean_exp the desired minimum mean expression in the bin.
##' @param rm_cv_quant the quantile threshold to remove CV outlier. Default NULL (i.e.
##' not used).
##' @param z_wins_th the threshold to winsorize Z-score. Default is 3
##' @param smooth_wsize the window size for smoothing. Default is 3.
##' @param cc_sd_th the number of SD used for the thresholds when defining cycling cells.
##' @param nb_pcs the number of PCs used in the community detection or tSNE. 
##' @param comm_k the number of nearest neighbor for the KNN graph. Default 100.
##' @param viz which method to use for visualization ('tsne', 'umap' or 'both'). Default is
##' 'tsne'.
##' @param tsne.seed the seed for the tSNE.
##' @param rcpp use Rcpp function. Default is TRUE. More memory-efficient and
##' faster when running on one core.
##' @return a data.frame with QC, community and tSNE for each cell.
##' @author Jean Monlong
##' @export
auto_cna_signal <- function(data, genes_coord, prefix='scCNAutils_out', nb_cores=1,
                            pause_after_qc=FALSE, use_cache=TRUE, sample_names=NULL,
                            info_df=NULL, 
                            max_mito_prop=.2, min_total_exp=0, cells_sel=NULL,
                            chrs=c(1:22,"X","Y"), cell_cycle=NULL, bin_mean_exp=3,
                            rm_cv_quant=NULL,
                            z_wins_th=3, smooth_wsize=3, cc_sd_th=3, nb_pcs=10,
                            comm_k=100, viz=c('tsne','umap','both'), tsne.seed=999,
                            rcpp=TRUE){
  ## Cache options
  info.file = paste0(prefix, '-sampleinfo.RData')
  raw.file = paste0(prefix, '-ge.RData')
  skip.raw = file.exists(raw.file) & use_cache
  qc.file = paste0(prefix, '-qc.RData')
  skip.qc = file.exists(qc.file) & use_cache
  filter.file = paste0(prefix, '-ge-filter.RData')
  skip.filter = file.exists(filter.file) & use_cache
  norm.file = paste0(prefix, '-ge-coord-norm.RData')
  skip.norm = file.exists(norm.file) & use_cache
  bin.file = paste0(prefix, '-coord-norm-bin', bin_mean_exp, '.RData')
  skip.bin = file.exists(bin.file) & use_cache
  cv.lab = ifelse(is.null(rm_cv_quant), '', paste0('-rmcvq', rm_cv_quant))
  score.file = paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                      '-smooth', smooth_wsize, '.RData')
  skip.score = file.exists(score.file) & use_cache
  cnoc.file = paste0(prefix, '-noncycling.txt')
  skip.cnoc = file.exists(cnoc.file) & use_cache
  pca.file = paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                    '-smooth', smooth_wsize, '-pca.RData')
  skip.pca = file.exists(pca.file) & use_cache
  comm.file = paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                     '-smooth', smooth_wsize, '-comm', nb_pcs, 'PCs', comm_k,
                     '.RData')
  skip.comm = file.exists(comm.file) & use_cache
  ## Which of the big data are needed for the remaining steps
  need.raw = !skip.qc | !skip.filter
  need.filter = !skip.norm
  need.norm = !skip.bin
  need.bin = !skip.score
  need.score = !skip.pca

  ## Read raw data
  info.df = NULL
  if(skip.raw){
    if(need.raw){
      warning("Ignoring input data, loading cache files instead because use_cache=TRUE.")
      load(raw.file)
    }
  } else {
    message('Importing raw data...')
    if(is.character(data) & length(data)==1){
      data = read_mtx(path=data)
    } else if(is.character(data) & length(data) > 1){
      if(is.null(sample_names)){
        warning('sample_names is NULL, will try to guess sample names from data paths.')
        sample_names = basename(data)
      }
      data = lapply(data, function(path) read_mtx(path=path))
    }
    if(is.list(data) & is.data.frame(data[[1]])){
      if(is.null(sample_names)){
        sample_names = names(data)
      }
      ms.o = merge_samples(data, sample_names=sample_names)
      data = ms.o$ge
      info.df = ms.o$info
      save(info.df, file=info.file)
      save(data, file=raw.file)
    } else {
      save(data, file=raw.file)
    }
    if(any(is.na(data))){
      stop('Input data as NAs.')
      file.remove(raw.file)
    }
  }
  if(use_cache && file.exists(info.file) && is.null(info.df)){
    load(info.file)
  }

  ## Merge info
  if(!is.null(info_df)){
    if(is.null(info.df)){
      info.df = info_df
    } else {
      info.df = merge(info.df, info_df, by='cell', suffixes=c('','.pars'))
    }
  }

  ## QC
  if(skip.qc){
    load(qc.file)
  } else {
    message('QC...')
    qc.df = qc_cells(data, cell_cycle)
    qc.ggp = plot_qc_cells(qc.df, info_df=info.df)
    grDevices::pdf(paste0(prefix, '-qc.pdf'), 9, 7)
    lapply(qc.ggp, print)
    grDevices::dev.off()
    if(pause_after_qc){
      message('Inspect ', paste0(prefix, '-qc.pdf'), ' and rerun with "pause_after_qc=FALSE", eventually adjusting "max_mito_prop" and "min_total_exp".')
      return(list(qc=qc.df))
    }
    save(qc.df, file=qc.file)
  }

  ## Filter data based on QC
  if(skip.filter){
    if(need.filter){
      load(filter.file)
    }
  } else {
    message('QC filtering data...')
    data = qc_filter(data, qc.df, max_mito_prop, min_total_exp,
                     cells_sel=cells_sel)
    save(data, file=filter.file)
  }
  
  ## Coordinates and normalization
  if(skip.norm){
    if(need.norm){
      load(norm.file)
    }
  } else {
    message('Converting to coords and normalizing...')
    data = convert_to_coord(data, genes_coord, chrs)
    data = norm_ge(data, nb_cores=nb_cores, rcpp=rcpp)
    gene.info = gene_info(data, genes_coord)
    save(data, gene.info, file=norm.file)
  }
 
  ## Bin
  if(skip.bin){
    if(need.bin){
      load(bin.file)
    }
  } else {
    message('Binning...')
    data = bin_genes(data, bin_mean_exp, nb_cores, rcpp=rcpp)
    data = norm_ge(data, nb_cores=nb_cores, rcpp=rcpp)
    save(data, file=bin.file)
  }
  
  ## Scale and smooth
  if(skip.score){
    if(need.score){
      load(score.file)
    }
  } else {
    if(!is.null(rm_cv_quant)){
      message('Remove CV outliers...')
      data = rm_cv_outliers(data, ol_quant_th=rm_cv_quant)
    }
    message('Scaling...')
    data = zscore(data, z_wins_th, method='z')
    message('Smoothing...')
    data = smooth_movingw(data, smooth_wsize, nb_cores, rcpp=rcpp)
    save(data, file=score.file)
  }
  
  ## Potentially find cycling cells
  core_cells = NULL
  if(!is.null(cell_cycle)){
    if(skip.cnoc){
      core_cells = scan(cnoc.file, '', quiet=TRUE)
    } else {
      message('Finding cycling cells...')
      cc.l = define_cycling_cells(qc.df, cc_sd_th)
      core_cells = cc.l$cells.noc
      grDevices::pdf(paste0(prefix, '-qc-cellcycle.pdf'), 9, 7)
      lapply(cc.l$graphs, print)
      grDevices::dev.off()
      write(core_cells, file=paste0(prefix, '-noncycling.txt'))
    }
  }
  
  ## PCA
  if(skip.pca){
    load(pca.file)
  } else {
    message('PCA...')
    pca.o = run_pca(data, core_cells)
    grDevices::pdf(paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                          '-smooth', smooth_wsize, '-pcaSD.pdf'), 9, 7)
    print(pca.o$sdev.graph)
    print(pca.o$sdev.cumm.graph)
    grDevices::dev.off()
    save(pca.o, file=pca.file)
  }
  
  ## Community
  comm.df = NULL
  if(skip.comm){
    load(comm.file)
  } else {
    message('Detecting communities...')
    comm.l = find_communities(pca.o, nb_pcs, comm_k)
    comm.df = comm.l$comm
    comm.ggp = plot_communities(comm.df, qc_df=qc.df, info_df=info.df)
    grDevices::pdf(paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                          '-smooth', smooth_wsize, '-comm', nb_pcs, 'PCs', comm_k,
                          '.pdf'), 9, 7)
    lapply(comm.ggp, print)
    grDevices::dev.off()
    save(comm.df, file=comm.file)
  }

  if(viz[1] == 'umap' | viz[1] == 'both'){
    ## UMAP
    message('Computing UMAP...')
    umap.df = run_umap(pca.o, nb_pcs)
    umap.ggp = plot_umap(umap.df, qc_df=qc.df, comm_df=comm.df, info_df=info.df)
    grDevices::pdf(paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                          '-smooth', smooth_wsize, '-umap', nb_pcs, 'PCs.pdf'), 9, 7)
    lapply(umap.ggp, print)
    grDevices::dev.off()
    cells.df = umap.df
  }
  if(viz[1] == 'tsne' | viz[1] == 'both'){
    ## tSNE
    message('Computing tSNE...')
    tsne.df = run_tsne(pca.o, nb_pcs, seed=tsne.seed)
    tsne.ggp = plot_tsne(tsne.df, qc_df=qc.df, comm_df=comm.df, info_df=info.df)
    grDevices::pdf(paste0(prefix, '-coord-norm-bin', bin_mean_exp, cv.lab, '-z', z_wins_th,
                          '-smooth', smooth_wsize, '-tsne', nb_pcs, 'PCs.pdf'), 9, 7)
    lapply(tsne.ggp, print)
    grDevices::dev.off()
    cells.df = tsne.df
  }
  if(viz[1]=='both'){
    cells.df = merge(tsne.df, umap.df)
  }
  
  ## Master data.frame with QC, community and tSNE info
  message('Merging results...')
  res.df = merge(qc.df, comm.df)
  res.df = merge(res.df, cells.df)
  if(!is.null(info.df)){
    res.df = merge(res.df, info.df)
  }
  return(res.df)
}
