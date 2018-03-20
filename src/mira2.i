/*
 * mira2.i -
 *
 * Implement version 2 of MiRA (Multi-aperture Image Reconstruction Algorithm)
 * in Yeti/Yorick.
 *
 *-----------------------------------------------------------------------------
 *
 * This file is part of MiRA, a "Multi-aperture Image Reconstruction
 * Algorithm", <https://github.com/emmt/MiRA>.
 *
 * Copyright (C) 2001-2018, Éric Thiébaut <eric.thiebaut@univ-lyon1.fr>
 *
 * MiRA is free software; you can redistribute it and/or modify it under the
 * terms of the GNU General Public License version 2 as published by the Free
 * Software Foundation.
 *
 * MiRA is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 */

local MIRA_DEBUG, MIRA_QUIET;
/* DOCUMENT MIRA_DEBUG - perform debug checks?
         or MIRA_QUIET - suppress (some) warning messages?

     Global variables defined by MiRA to globally set debug and quiet modes.
 */
MIRA_DEBUG = 1n;
MIRA_QUIET = 0n;

/* The following function is a duplicate of the one in "utils.i" which is
   needed to initialize the paths in MiRA software. */
func mira_absdirname(file)
/* DOCUMENT mira_absdirname(file);

     yields the absolute directory name of FILE which can be a file name or a
     file stream.  The returned string is always an absolute directory name
     (i.e., starting by a "/") terminated by a "/".

   SEE ALSO: dirname, filepath, strfind. */
{
  if ((i = strfind("/", (path = filepath(file)), back=1)(2)) <= 0) {
    error, "expecting a valid file name or file stream";
  }
  return strpart(path, 1:i);
}

func mira_require(pkgfunc, pkgdir, pkgsrc)
/* DOCUMENT mira_require, pkgfunc, pkgdir, pkgsrc;

     If PKGFUNC is not the name of an existing (interpreted or builtin)
     function, this subroutine attempts to load file PKGSRC, possibly in
     subdirectoy PKGDIR of the sub-packages of MiRA.  An error is raised if
     PKGFUNC is not the name of an existing function after trying to include
     file PKGSRC in relevant directories

   SEE ALSO: include, is_func, require.
 */
{
  path = "";
  pass = 0;
  while (! symbol_exists(pkgfunc) ||
         (c = is_func(symbol_def(pkgfunc))) == 0n || c == 3n) {
    if (strlen(path) > 0) {
      error, "function "+pkgfunc+" not defined in \""+path+"\"";
    }
    if (++pass == 1) {
      /* Package may be installed next to MiRA source. */
      path = MIRA_HOME + pkgsrc;
    } else if (pass == 2) {
      /* May be no installation has been done and package is in the source tree
         of MiRA. */
      path = MIRA_HOME + "../lib/" + pkgdir + "/" + pkgsrc;
    } else if (pass == 3) {
      /* Package may be installed in a standard location. */
      path = pksrc;
    } else {
      error, "source file \""+pkgsrc+"\" not found";
    }
    if (open(path, "r", 1)) {
      include, path, 3;
    } else {
      path = "";
    }
  }
}

local MIRA_HOME, MIRA_VERSION;
/* DOCUMENT MIRA_HOME
         or MIRA_VERSION

     Global variables defined by MiRA with respectively the name of the source
     directory of MiRA and the version of MiRA.

   SEE ALSO:
 */
MIRA_VERSION = "2.0.0a";
MIRA_HOME = mira_absdirname(current_include());

/* FIXME: It necessary to make sure Yeti and other mandatory plugins are
   loaded before otherwise their functions may not be defined despite the
   `autoload` feature.  This issue seems to only occur in batch mode. */
if (is_func(h_new) != 2) {
  include, "yeti.i", 3;
  if (is_func(h_new) != 2) {
    error, ("cannot load mandatory Yeti extension " +
            "(https://github.com/emmt/Yeti)");
  }
}
if (is_func(opl_vmlmb) != 1) {
  include, "optimpacklegacy.i", 3;
  if (is_func(opl_vmlmb) != 1) {
    error, ("cannot load mandatory OptimPackLegacy extension " +
            "(https://github.com/emmt/OptimPackLegacy)");
  }
}
mira_require, "oifits_new", "yoifits", "oifits.i";
mira_require, "throw",      "ylib",    "utils.i";
mira_require, "rgl_new",    "ipy",     "rgl.i";
mira_require, "linop_new",  "ipy",     "linop.i";

/* Load other parts of MiRA (which should be at the same location of this
   file). */
include, MIRA_HOME+"mira2_utils.i", 1;
include, MIRA_HOME+"mira2_config.i", 1;
include, MIRA_HOME+"mira2_data.i", 1;
include, MIRA_HOME+"mira2_xform.i", 1;
include, MIRA_HOME+"mira2_cost.i", 1;
include, MIRA_HOME+"mira2_image.i", 1;
include, MIRA_HOME+"mira2_solver.i", 1;

/*
  MiRA structure:
     master.oidata = OI-FITS data
     master.stage = configuration stage of MiRA (0 initially, ≥ 1 after data
                    selection, ≥ 2 means all settings have been updated)
     master.coords = table of coordinates
     master.coords.u = baseline U-coordinate [m]
     master.coords.v = baseline V-coordinate [m]
     master.coords.wave = effective wavelength [m]
     master.coords.band = effective bandwidth [m]
     master.model.img = current model image
     master.model.vis = model complex visibility
     master.model.phi = phase of model complex visibility
     master.model.amp = amplitude of model complex visibility
     master.model.re = real part of model complex visibility
     master.model.im = imaginary part of model complex visibility
     master.xform = linear transform
     master.smearingfactor = scaling factor for the bandwidth smearing
     master.smearingfunction = function to shape the bandwidth smearing
     master.wavemin = minimal wavelength (in meters)
     master.wavemax = maximal wavelength (in meters)
     master.pixelsize = pixel size (in radians)
     master.dims = image dimensions (in pixels) as returned by `dimsof`
     master.target = name of target (as found in OI-FITS data)
     master.baseline_precision = precision for rounding baselines (in meters)
     master.flags = processiong options

     FIXME:
     master.datalist = list of data blocks
     master.db1 ... master.dbN = selected datablocks of data to fit

     master.dbK.oidb  = link to OI-FITS datablock
     master.dbK.oiref = indices of data in OI-FITS
     master.dbK.ops = table of operations
     master.dbK.sgn = sign for frequencies
     master.dbK.idx = index for frequencies in model
     master.dbK.*


     1. selection of target object

     master = mira_new(data, ..., target=..., wavemin=..., wavemax=...,
                       freqmin=..., freqmax=..., xform=..., dim=...,
                       pixelsize=...);
     mira_save, master, file; // save model to file
     mira_config, master, wavemin=..., wavemax=..., freqmin=..., freqmax=...,
                  xform=...,  dim=..., pixelsize=...;
     mira_update, master; // automatically done
     mira_apply(master, x) // apply direct transform to image x
     mira_apply(master, x, adj) // apply direct transform or its adjoint to x
     mira_cost(master, x) // yield objective function for image x
     mira_cost_and_gradient(master, x, g) // yield objective function and its
                                          // gradient for image x
 */

/*---------------------------------------------------------------------------*/
/* UTILITIES */

func mira_default_image(master)
/* DOCUMENT mira_default_image(master);
     Yields the default image for MiRA instance `master` which is a centered
     point-like source.

   SEE ALSO: mira_new.
 */
{
  img = array(double, mira_image_size(master));
  img(mira_image_size(master, 1)/2 + 1,
      mira_image_size(master, 2)/2 + 1) = 1.0;
  return img;
}

/*--------------------------------------------------------------------------*/
/* TABLES OF VIRTUAL OPERATIONS */

/* Instanciate the tables of virtual operations for the different data blocks.
   If the objects are already hash tables just refresh their contents. */

mira_define_table, _MIRA_VIS_OPS,
  class = "vis",
  cost = symlink_to_variable(_mira_vis_cost),
  ndata = symlink_to_variable(_mira_vis_ndata);

mira_define_table, _MIRA_VISAMP_OPS,
  class = "visamp",
  cost = symlink_to_variable(_mira_visamp_cost),
  ndata = symlink_to_variable(_mira_visamp_ndata);

mira_define_table, _MIRA_VISPHI_OPS,
  class = "visphi",
  cost = symlink_to_variable(_mira_visphi_cost),
  ndata = symlink_to_variable(_mira_visphi_ndata);

mira_define_table, _MIRA_VIS2_OPS,
  class = "vis2",
  cost = symlink_to_variable(_mira_vis2_cost),
  ndata = symlink_to_variable(_mira_vis2_ndata);

mira_define_table, _MIRA_T3_OPS,
  class = "t3",
  cost = symlink_to_variable(_mira_t3_cost),
  ndata = symlink_to_variable(_mira_t3_ndata);

mira_define_table, _MIRA_T3AMP_OPS,
  class = "t3amp",
  cost = symlink_to_variable(_mira_t3amp_cost),
  ndata = symlink_to_variable(_mira_t3amp_ndata);

mira_define_table, _MIRA_T3PHI_OPS,
  class = "t3phi",
  cost = symlink_to_variable(_mira_t3phi_cost),
  ndata = symlink_to_variable(_mira_t3phi_ndata);
