package inc::MBX::Alien::FLTK::Platform::Unix;
{
    use strict;
    use warnings;
    use Carp qw[];
    use Config qw[%Config];
    use lib '../../../../../';
    use inc::MBX::Alien::FLTK::Utility qw[_o _a _rel _abs can_run];
    use inc::MBX::Alien::FLTK;
    use base 'inc::MBX::Alien::FLTK::Base';
    $|++;

    sub configure {
        my ($self, @args) = @_;
        $self->quiet(1);
        $self->SUPER::configure();    # Get basic config data
        $self->notes(
            os_ver => ${
                my $x = `uname -r`;
                    $x =~ s|\D||g;
                    \$x
                }
        );

        # Asssumed true since this is *nix
        $self->notes('define')->{'USE_X11'} = !grep {m[^no_x11$]} @args;
        print "have pthread... yes (assumed)\n";
        $self->notes('define')->{'HAVE_PTHREAD'} = 1;
        $self->notes('ldflags' => $self->notes('ldflags') . ' -lpthread ');
        print "have sys/ndir.h... \n";
        $self->notes('define')->{'HAVE_SYS_NDIR_H'}
            = ($self->find_h('sys/ndir.h') ? 1 : undef);
        print "have sys/dir.h... \n";
        $self->notes('define')->{'HAVE_SYS_DIR_H'}
            = ($self->find_h('sys/dir.h') ? 1 : undef);
        print "have ndir.h... \n";
        $self->notes('define')->{'HAVE_NDIR_H'}
            = ($self->find_h('ndir.h') ? 1 : undef);
        {
            print
                'Checking whether we have the POSIX compatible scandir() prototype... ';
            my $obj = $self->compile({code => <<'' });
#include <dirent.h>
int func (const char *d, dirent ***list, void *sort) {
    int n = scandir(d, list, 0, (int(*)(const dirent **, const dirent **))sort);
}
int main ( ) {
    return 0;
}

            if ($obj ? 1 : 0) {
                print "yes\n";
                $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = 1;
            }
            else {
                print "no\n";
                $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = undef;
            }
        }
        {
            print "Checking string functions...\n";
            if (($self->notes('os') =~ m[^hpux$]i)
                && $self->notes('os_ver') == 1020)
            {   print
                    "\nNot using built-in snprintf function because you are running HP-UX 10.20\n";
                $self->notes('define')->{'HAVE_SNPRINTF'} = undef;
                print
                    "\nNot using built-in vnprintf function because you are running HP-UX 10.20\n";
                $self->notes('define')->{'HAVE_VNPRINTF'} = undef;
            }
            elsif (($self->notes('os') =~ m[^dec_osf$]i)
                   && $self->notes('os_ver') == 40)
            {   print
                    "\nNot using built-in snprintf function because you are running Tru64 4.0.\n";
                $self->notes('define')->{'HAVE_SNPRINTF'} = undef;
                print
                    "\nNot using built-in vnprintf function because you are running Tru64 4.0.\n";
                $self->notes('define')->{'HAVE_VNPRINTF'} = undef;
            }
        }
        {
            my %functions = (
                strdup      => 'HAVE_STRDUP',
                strcasecmp  => 'HAVE_STRCASECMP',
                strncasecmp => 'HAVE_STRNCASECMP',
                strlcat     => 'HAVE_STRLCRT',

                #strlcpy     => 'HAVE_STRLCPY'
            );
            for my $func (keys %functions) {
                printf 'Checking for %s... ', $func;
                my $obj = $self->compile({code => <<""});
/* Define $func to an innocuous variant, in case <limits.h> declares $func.
   For example, HP-UX 11i <limits.h> declares gettimeofday.  */
#define $func innocuous_$func
/* System header to define __stub macros and hopefully few prototypes,
    which can conflict with char $func (); below.
    Prefer <limits.h> to <assert.h> if __STDC__ is defined, since
    <limits.h> exists even on freestanding compilers.  */
#ifdef __STDC__
# include <limits.h>
#else
# include <assert.h>
#endif
#undef $func
/* Override any GCC internal prototype to avoid an error.
   Use char because int might match the return type of a GCC
   builtin and then its argument prototype would still apply.  */
#ifdef __cplusplus
extern "C"
#endif
char $func ();
/* The GNU C library defines this for functions which it implements
    to always fail with ENOSYS.  Some functions are actually named
    something starting with __ and the normal name is an alias.  */
#if defined __stub_$func || defined __stub___$func
choke me
#endif
int main () {
    return $func ();
    return 0;
}

                if ($obj) {
                    print "yes\n";
                    $self->notes('define')->{$functions{$func}} = 1;
                }
                else {
                    print "no\n";
                    $self->notes('define')->{$functions{$func}} = undef;
                }
            }
        }
        {

            # Use the X overlay extension for MenuWindow and Tooltips. Pretty
            # much depreciated, this will add a substantial amount of code
            # to manage more than one visual, and has only worked on Irix.
            # (ignored if !USE_X11)
            print 'Checking for overlay... ';
            if (`xprop -root 2>/dev/null | grep -c "SERVER_OVERLAY_VISUALS"`)
            {   print "yes\n";
                $self->notes('define')->{'HAVE_OVERLAY'} = 1;
            }
            else { print "no\n" }
        }
        {    # X11 stuff
            {
                last if grep {m[^no_x11$]} @args;
                $self->notes('define')->{'USE_X11'} = 1;
                print 'Checking for X11 libs... ';
                $self->notes('can_has_x11', 0);
                for my $incdir ($self->_x11_()) {
                    my $libdir = $incdir;
                    $libdir =~ s|include|lib|;
                    if ($self->assert_lib({lib     => 'X11',
                                           libpath => $libdir,
                                           header  => 'X11/Xlib.h',
                                           incpath => $incdir
                                          }
                        )
                        )
                    {   $self->notes('include_dirs')->{_abs($incdir)}++;
                        $self->notes('ldflags' => " -L$libdir -lX11 "
                                     . $self->notes('ldflags'));
                        $self->notes('can_has_x11', 1);
                        print "okay\n";
                        last;
                    }
                }
                if (!$self->notes('can_has_x11')) {
                    $self->_error({stage   => 'configure',
                                   fatal   => 1,
                                   message => <<'' });
Failed to find the X11 libs. You probably need to install the X11 development
package first. On Debian Linux, these are the packages libx11-dev and x-dev.
If I'm just missing something... patches welcome.

                }
            }
            {

                #
                print 'Checking for Xcursor libs... ';
                $self->notes('define')->{'USE_XCURSOR'} = 0;
                for my $incdir ($self->_x11_()) {
                    my $libdir = $incdir;
                    $libdir =~ s|include|lib|;
                    if ($self->assert_lib({lib     => 'X11/Xcursor',
                                           libpath => $libdir,
                                           header  => 'Xcursor/Xcursor.h',
                                           incpath => $incdir
                                          }
                        )
                        )
                    {   $self->notes('include_dirs')->{_abs($incdir)}++;
                        $self->notes('ldflags' => " -L$libdir -lXcursor  "
                                     . $self->notes('ldflags'));
                        $self->notes('define')->{'USE_XCURSOR'} = 1;
                        print "okay\n";
                        last;
                    }
                }
                if (!$self->notes('define')->{'USE_XCURSOR'}) {
                    $self->_error({stage   => 'configure',
                                   fatal   => 0,
                                   message => <<'' });
Failed to find the XCursor libs. You probably need to install the X11
development package first. On Debian Linux, these are the packages libx11-dev,
x-dev, and libxcursor-dev. If I'm just missing something... patches welcome.

                }
            }
            {

                #
                print 'Checking for Xi libs... ';
                my $Xi_okay = 0;
            XI: for my $incdir ($self->_x11_()) {
                    my $libdir = $incdir;
                    $libdir =~ s|include|lib|;
                    if ($self->assert_lib({lib     => [qw[Xi Xext]],
                                           libpath => $libdir,
                                           header  => [
                                                    'X11/extensions/XInput.h',
                                                    'X11/extensions/XI.h'
                                           ],
                                           incpath => $incdir
                                          }
                        )
                        )
                    {   $self->notes('include_dirs')->{_abs($incdir)}++;
                        $self->notes('ldflags' => " -L$libdir -lXext -lXi "
                                     . $self->notes('ldflags'));
                        $Xi_okay = 1;
                        print "okay\n";
                        last XI;
                    }
                }
                if (!$Xi_okay) {
                    $self->_error({stage   => 'configure',
                                   fatal   => 1,
                                   message => <<'' });
Failed to find the XInput Extension. You probably need to install the XInput
Extension development package first. On Debian Linux, this is the libxi-dev
package. If I'm just missing something... patches welcome.

                }
            }
        }
    GL: {
            last if grep {m[^no_gl$]} @args;
            print 'Checking for GL... ';
            my $GL_LIB = '';
            $self->notes('define')->{'HAVE_GL'} = 0;
        GL_LIB: for my $_GL_lib (qw[GL MesaGL]) {
                if ($self->assert_lib({lib    => $_GL_lib,
                                       header => 'GL/gl.h'
                                      }
                    )
                    )
                {   $GL_LIB = '-l' . $_GL_lib;
                    $self->notes('define')->{'HAVE_GL'} = 1;
                    print "okay ($GL_LIB)\n";
                    last GL_LIB;
                }
            }
            if (!$GL_LIB) {
                $self->_error(
                    {stage => 'configure',
                     fatal => 0,
                     message =>
                         'OpenGL libs were not found (tried both GL and MesaGL)'
                    }
                );
            }
            if ($GL_LIB && $self->notes('define')->{'HAVE_GL_GLU_H'}) {
                print 'Checking for GL/glu.h... ';
                if ($self->assert_lib({lib    => 'GLU',
                                       header => 'GL/glu.h'
                                      }
                    )
                    )
                {   $self->notes('define')->{'HAVE_GL_GLU_H'} = 1;
                    print "okay\n";
                    $GL_LIB = " -lGLU  $GL_LIB ";
                }
                else { print "no\n" }
            }
            $self->notes(GL => $GL_LIB);
        }
        $self->quiet(0);
        return 1;
    }

    sub _x11_ {    # Common directories for X headers. Check X11 before X11R\d
        return     # because it is often a symlink to the current release.
            qw[
            /usr/X11/include
            /usr/X11R7/include          /usr/X11R6/include
            /usr/X11R5/include          /usr/X11R4/include
            /usr/include
            /usr/include/X11R7          /usr/include/X11R6
            /usr/include/X11R5          /usr/include/X11R4
            /usr/local/X11/include
            /usr/local/X11R7/include    /usr/local/X11R6/include
            /usr/local/X11R5/include    /usr/local/X11R4/include
            /usr/local/include
            /usr/local/include/X11R7    /usr/local/include/X11R6
            /usr/local/include/X11R5    /usr/local/include/X11R4
            /usr/X386/include           /usr/x386/include
            /usr/XFree86/include
            /usr/include                /usr/local/include
            /usr/unsupported/include
            /usr/athena/include
            /usr/local/x11r5/include
            /usr/lpp/Xamples/include
            /usr/openwin/include        /usr/openwin/share/include   ];
    }
    1;
}

=pod

=head1 Author

Sanko Robinson <sanko@cpan.org> - http://sankorobinson.com/

CPAN ID: SANKO

=head1 License and Legal

Copyright (C) 2009 by Sanko Robinson E<lt>sanko@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it under
the terms of The Artistic License 2.0. See the F<LICENSE> file included with
this distribution or http://www.perlfoundation.org/artistic_license_2_0.  For
clarification, see http://www.perlfoundation.org/artistic_2_0_notes.

When separated from the distribution, all POD documentation is covered by the
Creative Commons Attribution-Share Alike 3.0 License. See
http://creativecommons.org/licenses/by-sa/3.0/us/legalcode.  For
clarification, see http://creativecommons.org/licenses/by-sa/3.0/us/.

=for git $Id: Unix.pm dc42150 2010-01-17 03:51:57Z sanko@cpan.org $

=cut
