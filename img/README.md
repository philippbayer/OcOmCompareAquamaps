To make example.png:

shp <- get_shapes('CoCosV10I_16S_phyloseq_nt.rds')
ggsave(plot_shapes(shp), filename='img/example.png', height=10, width=10, dpi=300)
