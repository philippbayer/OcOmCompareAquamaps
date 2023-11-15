#' Calculates Aquamaps-based Probabilities for all ASVs
#'
#' @name OcOmCompareAquamaps
NULL

#' Get Aquamaps-based Probability values
#'
#' Joins the ASV-based sightings data with the Aquamaps
#' C-squares and returns the Aquamaps-probabilities for each
#' species.
#'
#' @param rds A RDS phyloseq object as returned by the ampliseq pipeline
#' @param reads_cutoff The number of reads for an ASV to be included in
#'        the analysis. Default is 10.
#' @param db_file Location of the Aquamaps database. Default is
#'        paste0(rappdirs::app_dir("aquamaps")$config(), '/am.db')
#' @export
#' @examples
#' shp <- get_shapes('some_examples.rds')
get_shapes <- function(rds,
                       read_cutoff = 10,
                       db_file = paste0(rappdirs::app_dir("aquamaps")$config(), '/am.db')) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_file)

  a <- readRDS(rds)

  asvs_to_location <-
    a@otu_table |> as.data.frame() |>
    dplyr::as_tibble(rownames = 'ASV') |>
    tidyr::pivot_longer(-ASV, names_to = 'Location', values_to = 'Reads') |>
    dplyr::filter(Reads > 0)

  asvs_to_species <- a@tax_table |> as.data.frame() |>
    tidyr::as_tibble(rownames = 'ASV') |>
    dplyr::select(ASV, species) |>
    dplyr::filter(species != 'dropped')

  location_to_latlong <- a@sam_data |> as.data.frame() |>
    tidyr::as_tibble(rownames = 'Location') |>
    dplyr::select(Location, latitude_dd, longitude_dd)

  asvs_to_species_and_location <- asvs_to_species |>
    dplyr::left_join(asvs_to_location, by ='ASV') |>
    dplyr::left_join(location_to_latlong, by = 'Location') |>
    dplyr::filter(!is.na(latitude_dd)) |>
    dplyr::filter(Reads > read_cutoff)

  all_species_seen <- asvs_to_species_and_location |>
    dplyr::pull(species) |>
    unique()


  # have a look
  all_species <- con |>
    dplyr::tbl(dplyr::sql('select * from speciesoccursum_r')) |>
    dplyr::collect() |>
    dplyr::mutate(full_species = paste(Genus, Species)) |>
    dplyr::filter(full_species %in% all_species_seen)

  # the aquamaps modeling data is in C-squares; these are
  # a CSIRO-developed map of boxes that cover the planet. Let's pull out the scores for each species in our table
  all_c_squares <- con %>%
    dplyr::tbl("hcaf_species_native") %>%
    dplyr::filter(SpeciesID %in% !!all_species$SpeciesID) |>
    dplyr::left_join(con |> dplyr::tbl('hcaf_r') |> dplyr::select(CsquareCode, NLimit, Slimit, WLimit, ELimit), by = 'CsquareCode') |>
    dplyr::collect() %>%
    dplyr::select(
      SpeciesID, CsquareCode,
      NLimit, Slimit, WLimit, ELimit,
      Probability)

  # now we have the squares; see whether our sightings overlap with these squares
  # this is a bit of a hack, but it works

  asvs_to_aquamaps_prob <- asvs_to_species_and_location |>
    # need to get the aquamaps species ID
    dplyr::left_join(all_species |> dplyr::select(SpeciesID, full_species), by = c('species' = 'full_species')) |>
    # now for each species, get all squares for that species (there's a nicer way of doing this)
    dplyr::left_join(all_c_squares, by  = c('SpeciesID'), relationship = "many-to-many") |>
    # now keep only the aquamaps squares that fit with the sighting latitude/longitude
    dplyr::filter(latitude_dd > Slimit, latitude_dd < NLimit, longitude_dd > WLimit, longitude_dd < ELimit)

  # we need the points of ASVs that don't have any overlap
  missing_asvs <- asvs_to_species_and_location |>
    dplyr::filter(! ASV %in% asvs_to_aquamaps_prob$ASV) |>
    dplyr::left_join(all_species |> dplyr::select(SpeciesID, full_species), by = c('species' = 'full_species'))

  # put the two tibbles together and return
  both <- dplyr::bind_rows(missing_asvs, asvs_to_aquamaps_prob)
  both <- both |> dplyr::mutate(Probability_class = dplyr::case_when(Probability > 0.99 ~ 'Great (>0.99)',
                                                       Probability > 0.5 ~ 'Good (>0.5)',
                                                       Probability > 0 ~ 'OK (>0)')) |>
    dplyr::mutate(Probability_class = factor(Probability_class, levels = c('Great (>0.99)', 'Good (>0.5)', 'OK (>0)')))

  DBI::dbDisconnect(con)

  both
}

#' Plot Aquamaps-based Probability values
#'
#' Takes the shape as produced by get_shapes()
#' and plots the probabilites for each ASV. A useful helper function.
#' @param table The large Probabilities table produced by get_shapes()
#' @param subset A vector with the names of ASVs to plot. Defaults to 10 at random that have a Probability.
#' @export
#' @examples
#' plot_shapes(get_shapes('some_examples.rds'))
plot_shapes <- function(table, subset = table |> dplyr::filter(!is.na(Probability)) |> dplyr::pull(ASV) |> unique()|> sample(10)) {
  my_sf <- sf::st_as_sf(table |>
                      dplyr::filter(ASV %in% subset), coords = c('longitude_dd', 'latitude_dd'))

  p <- ggplot(my_sf) +
    geom_sf(aes(color=log(Reads), shape = Probability_class), size = 3) +
    facet_wrap(~ASV+species) +
    labs(shape="Probability class")

  p
}
