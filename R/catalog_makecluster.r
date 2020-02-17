# ===============================================================================
#
# PROGRAMMERS:
#
# jean-romain.roussel.1@ulaval.ca  -  https://github.com/Jean-Romain/lidR
#
# COPYRIGHT:
#
# Copyright 2017 Jean-Romain Roussel
#
# This file is part of lidR R package.
#
# lidR is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# ===============================================================================

catalog_makecluster = function(ctg)
{
  # Bounding box of the catalog
  xmin <- ymin <- xmax <- ymax <- 0

  # Put some options in short named variables
  buffer  <- opt_chunk_buffer(ctg)
  by_file <- opt_chunk_is_file(ctg)
  start   <- opt_chunk_alignment(ctg)
  width   <- opt_chunk_size(ctg)

  # New feature from v2.2.0 to do not process some tiles
  processed <- ctg@data$processed
  if (is.null(processed)) processed <- rep(TRUE, nrow(ctg@data))
  if (!is.logical(processed)) stop("The attribute 'processed' of the catalog is not logical.", call. = FALSE)
  files <- ctg@data$filename[processed]

  # Creation of a set of rectangles that encompasses the whole catalog
  if (by_file)
  {
    xmin <- ctg@data[["Min.X"]]
    xmax <- ctg@data[["Max.X"]]
    ymin <- ctg@data[["Min.Y"]]
    ymax <- ctg@data[["Max.Y"]]

    xmin <- xmin[processed]
    xmax <- xmax[processed]
    ymin <- ymin[processed]
    ymax <- ymax[processed]
  }
  else
  {
    # Bounding box of the catalog
    bbox <- with(ctg@data, c(min(Min.X), min(Min.Y), max(Max.X), max(Max.Y)))

    # Shift to align the grid
    shift <- numeric(2)
    shift[1] <- (bbox[1] - start[1]) %% width
    shift[2] <- (bbox[2] - start[2]) %% width

    # Generate coordinates of bottom-left corner
    xmin <- seq(bbox[1] - shift[1], bbox[3], width)
    ymin <- seq(bbox[2] - shift[2], bbox[4], width)
    grid <- expand.grid(xmin = xmin, ymin = ymin)
    xmin <- grid$xmin
    ymin <- grid$ymin
    xmax <- xmin + width
    ymax <- ymin + width
  }

  verbose("Creating a set of clusters for the catalog...")

  # Generate center and width of each cluster
  xcenter <- (xmin + xmax)/2
  ycenter <- (ymin + ymax)/2
  width   <- xmax - xmin
  height  <- ymax - ymin

  # Creation of a set of clusters from the rectangles
  if (by_file && buffer <= 0)
  {
    clusters = lapply(1:length(xcenter), function(i)
    {
      center  <- list(x = xcenter[i], y = ycenter[i])
      cluster <- LAScluster(center, width[i], height[i], buffer, LIDRRECTANGLE, ctg@data$filename[i], "noname", proj4string = ctg@proj4string)

      cluster@select <- ctg@input_options$select
      cluster@filter <- paste(cluster@filter, ctg@input_options$filter)

      return(cluster)
    })
  }
  else
  {
    bboxes = mapply(raster::extent, xcenter - width/2, xcenter + width/2, ycenter - height/2, ycenter + height/2)
    clusters = suppressWarnings(catalog_index(ctg, bboxes, LIDRRECTANGLE, buffer, processed, TRUE, by_file))
    clusters = clusters[!sapply(clusters, is.null)]
  }

  # Post-process the clusters

  if (by_file & buffer == 0)
  {
    # Specific optimisation to remove the "-inside" filter
    clusters <- lapply(clusters, function(x)
    {
      x@filter <- ctg@input_options$filter
      return(x)
    })
  }

  # Record the path where to write the raster if requested
  if (opt_output_files(ctg) != "")
  {
    clusters <- lapply(seq_along(clusters), function(i)
    {
      X         <- list()
      X$ID      <- i
      X$XCENTER <- format(clusters[[i]]@center$x, scientific = F)
      X$XCENTER <- format(clusters[[i]]@center$y, scientific = F)
      X$XLEFT   <- format(clusters[[i]]@bbox[1], scientific = F)
      X$XRIGHT  <- format(clusters[[i]]@bbox[3], scientific = F)
      X$YBOTTOM <- format(clusters[[i]]@bbox[2], scientific = F)
      X$YTOP    <- format(clusters[[i]]@bbox[4], scientific = F)

      usefilename <- grepl("\\{ORIGINALFILENAME\\}",  opt_output_files(ctg))

      if (usefilename && !by_file)
        stop("The template {ORIGINALFILENAME} makes sense only when processing by file (chunk size = 0). It is undefined otherwise.", call. = FALSE)

      if (by_file)
        X$ORIGINALFILENAME <- tools::file_path_sans_ext(basename(files[i]))

      filepath  <- paste0(glue::glue_data(X, opt_output_files(ctg)))
      n         <- length(filepath)

      if (n > 1)
        stop(glue::glue("Ill-formed template string in the catalog: {n} filenames were generate for each chunk"), call. = FALSE)

      clusters[[i]]@save <- filepath
      return(clusters[[i]])
    })
  }

  # Record the alternative directories for remote computation
  if (ctg@input_options[["alt_dir"]][1] != "")
  {
    clusters <- lapply(seq_along(clusters), function(i)
    {
      clusters[[i]]@alt_dir <- ctg@input_options[["alt_dir"]]
      return(clusters[[i]])
    })
  }

  # Plot the catalog and the clusters if progress
  if (opt_progress(ctg))
  {
    xrange = c(min(xmin, ctg@data[["Min.X"]]), max(xmax, ctg@data[["Max.X"]]))
    yrange = c(min(ymin, ctg@data[["Min.Y"]]), max(ymax, ctg@data[["Max.Y"]]))
    title  = "Pattern of chunks"
    plot.LAScatalog(ctg, mapview = FALSE, chunk_pattern = FALSE, main = title, xlim = xrange, ylim = yrange)

    lapply(clusters, function(x)
    {
      graphics::rect(x@bbox[1], x@bbox[2], x@bbox[3], x@bbox[4], border = "red")

      if (x@buffer != 0)
        graphics::rect(x@bbbox[1], x@bbbox[2], x@bbbox[3], x@bbbox[4], border = "darkgreen", lty = "dotted")
    })
  }

  return(clusters)
}
