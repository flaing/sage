dnl Usage: SAGE_SHOULD_INSTALL_GCC(reason)
dnl
dnl Use this macro to indicate that we SHOULD install GCC.
dnl In this case, GCC will be installed unless SAGE_INSTALL_GCC=no.
dnl In the latter case, a warning is given.
AC_DEFUN([SAGE_SHOULD_INSTALL_GCC], [
    if test x$SAGE_INSTALL_GCC = xexists; then
        # Already installed in Sage, but it should remain selected
        true
    elif test x$SAGE_INSTALL_GCC = xno; then
        AC_MSG_WARN([$1])
    else
        AC_MSG_NOTICE([Installing GCC because $1])
        sage_spkg_install_gcc=yes
    fi
])

dnl Usage: SAGE_MUST_INSTALL_GCC(reason)
dnl
dnl Use this macro to indicate that we MUST install GCC.
dnl In this case, it is an error if SAGE_INSTALL_GCC=no.
AC_DEFUN([SAGE_MUST_INSTALL_GCC], [
    if test x$SAGE_INSTALL_GCC = xexists; then
        # Already installed in Sage, but it should remain selected
        true
    elif test x$SAGE_INSTALL_GCC = xno; then
        AC_MSG_ERROR([SAGE_INSTALL_GCC is set to 'no', but $1])
    else
        AC_MSG_NOTICE([Installing GCC because $1])
        sage_spkg_install_gcc=yes
    fi
])


dnl Test whether an existing GCC install in Sage exists and is broken
dnl If so set SAGE_BROKEN_GCC=yes
AC_DEFUN([SAGE_CHECK_BROKEN_GCC], [
    SAGE_BROKEN_GCC=no
    if test -n "$SAGE_LOCAL" -a -f "$SAGE_LOCAL/bin/gcc"; then
        if test -x "$SAGE_LOCAL/bin/g++"; then
            echo '#include <complex>' >conftest.cpp
            echo 'auto inf = 1.0 / std::complex<double>();' >>conftest.cpp

            if ! bash -c "source '$SAGE_SRC/bin/sage-env' && g++ -O3 -c -o conftest.o conftest.cpp"; then
                SAGE_BROKEN_GCC=yes
            fi
            rm -f conftest.*
        fi
    fi
])


SAGE_SPKG_CONFIGURE([gcc], [
	AC_REQUIRE([AC_PROG_CC])
	AC_REQUIRE([AC_PROG_CPP])
	AC_REQUIRE([AC_PROG_CXX])
	AC_REQUIRE([AC_PROG_OBJC])
	AC_REQUIRE([AC_PROG_OBJCXX])

    if test -f "$SAGE_LOCAL/bin/gcc"; then
        # Special value for SAGE_INSTALL_GCC if GCC is already installed
        SAGE_INSTALL_GCC=exists
        # Set yes since this implies we have already installed GCC and want to keep
        # it selected
        sage_spkg_install_gcc=yes

        # Check whether it actually works...
        # See https://trac.sagemath.org/ticket/24599
        SAGE_CHECK_BROKEN_GCC()
        if test x$SAGE_BROKEN_GCC = xyes; then
            # Prentend that GCC is not installed.
            # The gcc and g++ binaries as well as the "installed" file will
            # be removed by make before installing any packages such that
            # GCC will be built as if was never installed before.
            SAGE_INSTALL_GCC=yes
            SAGE_MUST_INSTALL_GCC([installed g++ is broken])
        fi
    elif test -n "$SAGE_INSTALL_GCC"; then
        # Check the value of the environment variable SAGE_INSTALL_GCC
        AS_CASE([$SAGE_INSTALL_GCC],
            [yes], [
                SAGE_MUST_INSTALL_GCC([SAGE_INSTALL_GCC is set to 'yes'])
            ], [no], [
                true
            ], [
                AC_MSG_ERROR([SAGE_INSTALL_GCC should be set to 'yes' or 'no'. You can also leave it unset to install GCC when needed])
            ])
    fi

    # Figuring out if we are using clang instead of gcc.
    AX_COMPILER_VENDOR()
    IS_REALLY_GCC=no
    if test "x$ax_cv_c_compiler_vendor" = xgnu ; then
        IS_REALLY_GCC=yes
    fi

    AX_CXX_COMPILE_STDCXX_11([], optional)
    if test $HAVE_CXX11 != 1; then
        SAGE_MUST_INSTALL_GCC([your C++ compiler does not support C++11])
    fi

    AC_LANG_PUSH(C)
    if test -z "$CC"; then
        SAGE_MUST_INSTALL_GCC([a C compiler is missing])
    fi

    # Save compiler before checking for C99 support
    save_CC=$CC
    # Check that we can compile C99 code
    AC_PROG_CC_C99()
    if test "x$ac_cv_prog_cc_c99" = xno; then
        SAGE_MUST_INSTALL_GCC([your C compiler cannot compile C99 code])
    fi
    # restore original CC
    CC=$save_CC
    AC_LANG_POP()

    if test x$GXX != xyes; then
        SAGE_SHOULD_INSTALL_GCC([your C++ compiler isn't GCC (GNU C++)])
    elif test $sage_spkg_install_gcc = yes; then
        # If we're installing GCC anyway, skip the rest of these version
        # checks.
        true
    elif test x$GCC != xyes; then
        SAGE_SHOULD_INSTALL_GCC([your C compiler isn't GCC (GNU C)])
    else
        # Since sage_spkg_install_gcc is "no", we know that
        # at least C, C++ and Fortran compilers are available.
        # We also know that all compilers are GCC.

        # Find out the compiler versions:
        AX_GCC_VERSION()
        AX_GXX_VERSION()

        if test $IS_REALLY_GCC = yes ; then
            # Add the .0 because Debian/Ubuntu gives version numbers like
            # 4.6 instead of 4.6.4 (Trac #18885)
            AS_CASE(["$GXX_VERSION.0"],
                [[[0-3]].*|4.[[0-7]].*], [
                    # Install our own GCC if the system-provided one is older than gcc-4.8.
                    SAGE_SHOULD_INSTALL_GCC([you have $CXX version $GXX_VERSION, which is quite old])
                ])
        fi

        # The following tests check that the version of the compilers
        # are all the same.
        if test "$GCC_VERSION" != "$GXX_VERSION"; then
            SAGE_SHOULD_INSTALL_GCC([$CC ($GCC_VERSION) and $CXX ($GXX_VERSION) are not the same version])
        fi

    fi

    # Check that the assembler and linker used by $CXX match $AS and $LD.
    # See http://trac.sagemath.org/sage_trac/ticket/14296
    if test -n "$AS"; then
        CXX_as=`$CXX -print-file-name=as 2>/dev/null`
        CXX_as=`command -v $CXX_as 2>/dev/null`
        cmd_AS=`command -v $AS`

        if test "$CXX_as" != "" -a "$CXX_as" != "$cmd_AS"; then
            SAGE_SHOULD_INSTALL_GCC([there is a mismatch of assemblers])
            AC_MSG_NOTICE([  $CXX uses $CXX_as])
            AC_MSG_NOTICE([  \$AS equal to $AS])
        fi
    fi
    if test -n "$LD"; then
        CXX_ld=`$CXX -print-file-name=ld 2>/dev/null`
        CXX_ld=`command -v $CXX_ld 2>/dev/null`
        cmd_LD=`command -v $LD`

        if test "$CXX_ld" != "" -a "$CXX_ld" != "$cmd_LD"; then
            SAGE_SHOULD_INSTALL_GCC([there is a mismatch of linkers])
            AC_MSG_NOTICE([  $CXX uses $CXX_ld])
            AC_MSG_NOTICE([  \$LD equal to $LD])
        fi
    fi

    dnl A stamp file indicating that an existing, broken GCC install should be
    dnl cleaned up by make.
    if test x$SAGE_BROKEN_GCC = xyes; then
        AC_CONFIG_COMMANDS([broken-gcc], [
            # Re-run the check just in case, such as when re-running
            # config.status
            SAGE_CHECK_BROKEN_GCC()
            if test x$SAGE_BROKEN_GCC = xyes; then
                touch build/make/.clean-broken-gcc
            fi
        ], [
            SAGE_LOCAL="$SAGE_LOCAL"
            SAGE_SRC="$SAGE_SRC"
        ])
    fi
])
