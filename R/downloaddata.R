#' Download the Aquamaps database
#' The location defaults to ~/.config/aquamaps
#'
#' I *think* this can be changed using rappdirs::app_dir("aquamaps")$config()
#' @param force Whether to overwrite an existing database file
#' @export
#' @examples
#' download_data()
download_data <- function(force = FALSE) {
  aquamapsdata::download_db(force)
}
