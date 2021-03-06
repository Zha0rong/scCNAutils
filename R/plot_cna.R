##' @title Heatmap of CNA
##' @param cna CNAs from \code{\link{call_cna}}.
##' @param chrs_order order of the chromosomes in the graph.
##' @return a ggplot2 graph
##' @author Jean Monlong
##' @export
##' @import ggplot2
plot_cna <- function(cna, chrs_order=c(1:22, 'X', 'Y')){
  CN = end = prop = start = wt.pv = NULL
  hmm.df = cna$hmm.df
  cna_df = cna$seg.df
  chrs_order = intersect(chrs_order, unique(cna_df$chr))
  if(length(chrs_order)==0){
    stop('Inconsistent chromosome names in "chrs_order".')
  }
  cna_df$chr = factor(cna_df$chr, levels=chrs_order)
  cna_df$CN = factor(cna_df$CN, levels=c('loss','neutral','gain'))

  ## Reorder community if it looks like numeric
  if(all(!is.na(suppressWarnings(as.numeric(unique(cna_df$community)))))){
    cna_df$community = as.numeric(cna_df$community)
    if(!('cell' %in% colnames(hmm.df))){
      hmm.df$community = as.numeric(hmm.df$community)
    }
  }

  ggp = list()
  if('prop' %in% colnames(cna_df)){
    ggp$heatmap = ggplot(cna_df, aes(xmin=start, xmax=end, ymin=-.5, ymax=.5, fill=CN, alpha=prop)) +
      geom_rect() + facet_grid(community~chr, scales='free', space='free') + theme_bw() +
      scale_fill_manual(values=c('steelblue','white','indianred')) + xlab('position') +
      ylab('community') + scale_alpha_continuous(name='prop of\nmetacells') + 
      theme(strip.text.y=element_text(angle=0), axis.text.y=element_blank(),
            axis.text.x=element_blank(), legend.position='bottom',
            panel.spacing=unit(0, 'cm'), axis.ticks.y=element_blank(),
            axis.ticks.x=element_blank())
  } else if('wt.pv' %in% colnames(cna_df)){
    cna_df$wt.pv = ifelse(is.na(cna_df$wt.pv), 1, cna_df$wt.pv)
    ggp$heatmap = ggplot(cna_df, aes(xmin=start, xmax=end, ymin=-.5,
                       ymax=.5, fill=CN,
                       alpha=winsor(-log10(wt.pv), 10))) +
      geom_rect() + facet_grid(community~chr, scales='free', space='free') +
      theme_bw() +
      scale_fill_manual(values=c('steelblue','grey','indianred')) +
      xlab('position') +
      ylab('community') + 
      theme(strip.text.y=element_text(angle=0), axis.text.y=element_blank(),
            axis.text.x=element_blank(), legend.position='bottom',
            panel.spacing=unit(0, 'cm'), axis.ticks.y=element_blank(),
            axis.ticks.x=element_blank())
    if(length(unique(cna_df$wt.pv))>1){
      ggp$heatmap = ggp$heatmap +
        scale_alpha_continuous(name='Wilcoxon test\n-log10(pv)', range=0:1,
                               breaks=seq(0,10,2), labels=c(seq(0,8,2), '>=10'))
    }
  } else {
    cna_df = cna_df[which(cna_df$pass.filter),]
    ggp$heatmap = ggplot(cna_df, aes(xmin=start, xmax=end, ymin=-.5, ymax=.5, fill=CN, alpha=winsor(length, 10))) +
      geom_rect() + theme_bw() + xlab('position') + ylab('community') +
      scale_fill_manual(values=c('steelblue','white','indianred')) +
      scale_alpha_continuous(name='nb bins\nwinsorized at 10',
                         range=c(.2,1)) + 
      theme(strip.text.y=element_text(angle=0), axis.text.y=element_blank(),
            axis.text.x=element_blank(), legend.position='bottom',
            panel.spacing=unit(0, 'cm'), axis.ticks.y=element_blank(),
            axis.ticks.x=element_blank())
    if('cell' %in% colnames(cna_df)){
      ggp$heatmap = ggp$heatmap + facet_grid(cell~chr, scales='free', space='free')
    } else {
      ggp$heatmap = ggp$heatmap + facet_grid(community~chr, scales='free', space='free')
    }
  }

  ## HMM output, one graph per chromosome
  for(ch in chrs_order){
    hmm.chr = hmm.df[which(hmm.df$chr==ch),]
    gp = ggplot(hmm.chr, aes(x=start, y=mean, colour=CN)) +
      geom_hline(yintercept=log(c(.5, 1, 1.5)), linetype=2) + 
      geom_point() +
      theme_bw() + xlab('position') + ggtitle(ch) + 
      scale_colour_brewer(palette='Set1') + 
      theme(axis.text.x=element_blank())
    if('cell' %in% colnames(hmm.chr)){
      gp = gp + facet_wrap(~cell)
    } else {
      gp = gp + facet_wrap(~community)
    }
    gp = list(gp)
    names(gp) = paste0('hmm', ch)
    ggp = c(ggp, gp)
  }
  
  return(ggp)
}
