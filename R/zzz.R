.onAttach <- function(libname, pkgname) {
  packageStartupMessage("This is version ", utils::packageVersion(pkgname),
                        " of ", pkgname, '. If you have not done so, please run download_data() to download the Aquamaps database.')
}
