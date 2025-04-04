/* mira_models.i --
 *
 * A standalone version of the models assumed in MiRA.
 */

local mira_build_separable_pix2vis, _mira_apply_separable_pix2vis;
/* DOCUMENT A = mira_build_separable_pix2vis(x, y, ufreq, vfreq);
        or  A = mira_build_separable_pix2vis(x, y, u, v, wave);

     Build an object representing the pixels to complex visibilities linear transform. The
     coefficients of the transform are stored in a compact form assuming that the
     transform is separable.

     Arguments `x` and `y` are the sky angular coordinates respectively along the 1st and
     2nd dimensions of the image model. Arguments `u` and `v` are the coordinates of the
     projected baselines for each model complex visibility. Argument `wave` specifies the
     wavelength(s) for the given baselines.

     If `wave` is not specified, `u` and `v` are assumed to specify the spatial
     frequencies.

     The object is used as: `A(arr, adj)` or apply the transform (or its adjoint if `adj`
     is true) to array `arr`.
 */
func mira_build_separable_pix2vis(x, y, u, v, wave)
{
    if (is_void(wave)) {
        // Assume that `u` and `v` are frequencies.
        q = -2*pi;
    } else {
        // Assume that `u` and `v` are projected baseline coordinates.
        q = -2*pi/wave;
    }
    a1 = (q*u)(-,..)*mira_as_vector(x);
    a2 = (q*v)(-,..)*mira_as_vector(y);
    return h_functor("_mira_apply_separable_pix2vis",
                     H1re = cos(a1),
                     H1im = sin(a1),
                     H2re = cos(a2),
                     H2im = sin(a2));
}

func _mira_apply_separable_pix2vis(A, arr, adj)
{
    if (! adj) {
        /* Direct transform. */
        if (numberof(dimsof(arr)) != 3) {
            error, "expecting a 2-dimensional array";
        }
        if (structof(arr) == complex) {
            error, "expecting a non-complex argument";
        }
        // Compute H1*arr by real-complex multiplications.
        re = arr(+,)*A.H1re(+,..);
        im = arr(+,)*A.H1im(+,..);
        // Multiply by H2 by complex-complex multiplications.
        return _mira_fake_complex((A.H2re*re)(sum,..) - (A.H2im*im)(sum,..),
                                  (A.H2re*im)(sum,..) + (A.H2im*re)(sum,..));
    } else {
        /* Apply adjoint operator */
        if (numberof((dims = dimsof(arr))) != 3 || dims(2) != 2) {
            error, "expecting a 2-by-m array";
        }
        re = arr(1,..)(-,..);
        im = arr(2,..)(-,..);
        return (A.H1re(,*)(,+)*(A.H2re*re + A.H2im*im)(,*)(,+) +
                A.H1im(,*)(,+)*(A.H2re*im - A.H2im*re)(,*)(,+));
    }
}

local mira_build_nonseparable_pix2vis, _mira_apply_nonseparable_pix2vis;
/* DOCUMENT A = mira_build_nonseparable_pix2vis(x, y, u, v, wave, band);

     Build an object representing the pixels to complex visibilities linear transform. The
     coefficients of the transform are stored as a general matrix not assuming that the
     transform is separable. This is adapted to account for bandwidth smearing.

     Arguments `x` and `y` are the sky angular coordinates respectively along the 1st and
     2nd dimensions of the image model. Arguments `u` and `v` are the baseline coordinates
     for each model complex visibility. Arguments `wave` and `band` specify the
     wavelength(s) and spectral bandwidth(s) for the given baselines.

     Keywords `smearingfunction` and `smearingfactor` are to specify the function and the
     multiplier for the bandwidth smearing.

     The object is used as: `A(arr, adj)` or apply the transform (or its adjoint if `adj`
     is true) to array `arr`.
 */
func mira_build_nonseparable_pix2vis(x, y, u, v, wave, band, smearingfunction=, smearingfactor=)
{
    x = mira_as_vector(x);
    y = mira_as_vector(y);
    B = mira_build_separable_pix2vis(x, y, u, v, wave);
    H1re = h_pop(B, "H1re")(,-,..); // insert a 2nd dimension
    H1im = h_pop(B, "H1im")(,-,..); // insert a 2nd dimension
    H2re = h_pop(B, "H2re")( -,..); // insert a 1st dimension
    H2im = h_pop(B, "H2im")( -,..); // insert a 1st dimension
    H = _mira_fake_complex(H1re*H2re - H1im*H2im,  // real(H)
                           H1re*H2im + H1im*H2re); // imag(H)
    if (! is_void(smearingfunction)) {
        r = band/(wave*wave);
        if (! is_void(smearingfactor)) r *= smearingfactor;
        r = smearingfunction((r*u)(-,-,..)*x + (r*v)(-,-,..)*y(-,));
        H(1,..) *= r;
        H(2,..) *= r;
    }
    return h_functor("_mira_apply_nonseparable_pix2vis", H);
}

func _mira_apply_nonseparable_pix2vis(A, arr, adj)
{
  return mvmult(A.H, arr, adj);
}

local mira_build_nfft_pix2vis, _mira_apply_nfft_pix2vis;
/* DOCUMENT A = mira_build_nfft_pix2vis(x, y, u, v, wave);

     Build an object representing the pixels to complex visibilities linear transform. The
     result is a fast separable transform computed by NFFT.

     Arguments `x` and `y` are the sky angular coordinates respectively along the 1st and
     2nd dimensions of the image model. Arguments `u` and `v` are the baseline coordinates
     for each model complex visibility. Argument `wave` specifies the wavelength(s) for
     the given baselines.

     Keywords `nthreads` and `flags` are to specify the number of threads to compute the
     FFT and FFTW flags.

     The object is used as: `A(arr, adj)` or apply the transform (or its adjoint if `adj`
     is true) to array `arr`.
 */
func mira_build_nfft_pix2vis(x, y, u, v, wave, nthreads=, flags=)
{
    /* Make sure NFFT plugin is installed and loaded. */
    if (is_func(nfft_new) != 2) {
        include, "nfft.i", 3;
        if (! is_func(nfft_new)) {
            write, format="%s \"%s\". %s \"%s\".\n",
                "YNFFT plugin is not installed, see",
                "https://github.com/emmt/ynfft",
                "Depending on your system, you may just have to install package",
                "yorick-ynfft";
            error, "plugin YNFFT is not installed";
        }
    }

    /*
     * In NFFT:
     *   x = [-nx/2, 1-nx/2, ..., nx/2-1]*step
     *   y = [-ny/2, 1-ny/2, ..., ny/2-1]*step
     * plus NX and NY must be even.
     */
    local r1, r2;
    x = mira_as_vector(x);
    nx = numberof(x);
    if ((nx & 1) == 1) {
        n1 = nx + 1;
        r1 = 2 : n1;
    } else {
        n1 = nx;
    }
    y = mira_as_vector(y);
    ny = numberof(y);
    if ((ny & 1) == 1) {
        n2 = ny + 1;
        r2 = 2 : n2;
    } else {
        n2 = ny;
    }
    if (is_void(flags)) flags = NFFT_SORT_NODES;
    nodes = [(avg(x(dif))/wave)*u,
             (avg(y(dif))/wave)*v];
    dims = [n1, n2];
    return h_functor("_mira_apply_nfft_pix2vis",
                     nfft = nfft_new(dims, nodes, flags=flags, nthreads=nthreads),
                     n1 = n1, r1 = r1,
                     n2 = n2, r2 = r2,
                     sub = (n1 != nx || n2 != ny));
}

func _mira_apply_nfft_pix2vis(A, arr, adj)
{
    local z;
    if (! adj) {
        /* direct operator */
        if (A.sub) {
            tmp = array(complex, A.n1, A.n2);
            tmp(A.r1, A.r2) = arr;
            eq_nocopy, arr, tmp;
        }
        reshape, z, &A.nfft(arr), double, 2, A.nfft.num_nodes;
        return z;
    } else {
        /* adjoint operator */
        z = A.nfft(mira_cast_real_as_complex(arr), 1n);
        if (A.sub) {
            return double(z)(A.r1, A.r2);
        } else {
            return double(z);
        }
    }
}

local mira_pix2vis;
/* DOCUMENT vis = mira_pix2vis(img, u, v, wave=, band=, pixelsize=,
                               smearingfactor=, smearingfunction=);

     Apply the pixels to visibilities transform to image `img` for projected baselines of
     coordinates given by `u` and `v`. The result is an array of complex visibilities
     computed as assumed by the different possible models in MiRA.

     Mandatory keywords `wave` and `band` specify the wavelength(s) and the spectral
     bandwidth(s).

     Mandatory keyword `pixelsize` gives the size of the pixels.

     Optional keywords `smearingfunction` and `smearingfactor` are to specify the function
     and the multiplier for the bandwidth smearing.

 */
func mira_pix2vis(img, u, v, wave=, band=, pixel_size=, smearingfunction=, smearingfactor=)
{
    dims = dimsof(img);
    if (numberof(dims) != 3) {
        error, "expecting a 2-dimensional array";
    }
    if (structof(img) == complex) {
        error, "expecting a non-complex argument";
    }
    x = mira_image_coordinates(dims(2), pixelsize);
    y = mira_image_coordinates(dims(3), pixelsize);

    // Multiply the image by the smearing if any.
    local z;
    if (! is_void(smearingfunction)) {
        r = band/(wave*wave);
        if (! is_void(smearingfactor)) r *= smearingfactor;
        z = img*smearingfunction((r*u)(-,-,..)*x + (r*v)(-,-,..)*y(-,));
    } else {
        eq_nocopy, z, img;
    }

    // Real-complex multiplication by H1.
    q = -2*pi/wave;
    a1 = (q*u)(-,..)*x;
    H1re = cos(a1);
    H1im = sin(a1);
    re = H1re(+,..)*z(+,..);
    im = H1im(+,..)*z(+,..);

    // Complex-complex multiplication by H2.
    a2 = (q*v)(-,..)*y;
    H2re = cos(a2);
    H2im = sin(a2);
    return mira_as_complex(H2re(+,..)*re(+,..) - H2im(+,..)*im(+,..),
                           H2re(+,..)*im(+,..) + H2im(+,..)*re(+,..));
}

func mira_as_complex(re, im)
{
    local z;
    dims = dimsof(re, im);
    tmp = array(double, 2, );
    tmp(1,..) = unref(re);
    tmp(2,..) = unref(im);
    reshape, z, &tmp, complex, dims;
    return z;
}

/* DOCUMENT mira_as_vector(x)

     Return a vector of values from `x` which can be a vector or a range.

*/
func mira_as_vector(x)
{
    if (is_vector(x)) return x;
    if (typeof(x) == "range") return indgen(x);
    error, "expecting a vector or a range";
}

func mira_image_coordinates(n, s)
/* DOCUMENT mira_image_coordinates(n, s);

     yields a vector of `n` coordinates with step `s` and centered according to
     conventions in `fftshift` and `nfft`.

   SEE ALSO: fftshift, nfft.
 */
{
    return double(s)*indgen(-(n/2):n-1-(n/2))
}

// FIXME: Exact copy of `_mira_fake_complex`.
func _mira_fake_complex(re, im)
{
    z = array(double, 2, dimsof(re, im));
    z(1,..) = re;
    z(2,..) = im;
    return z;
}
