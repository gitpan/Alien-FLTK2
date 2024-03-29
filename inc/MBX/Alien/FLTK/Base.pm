package inc::MBX::Alien::FLTK::Base;
{
    use strict;
    use warnings;
    use Cwd;
    use Config qw[%Config];
    use File::Temp qw[tempfile];
    use File::Find qw[find];
    use Carp qw[carp];
    use base 'Module::Build';
    use lib '../../../../';
    use inc::MBX::Alien::FLTK::Utility qw[can_run run _o _a _exe _dll _path
        _realpath _abs _rel _dir _file _split _cwd];
    use lib '.';

    sub fltk_dir {
        my ($self, $extra) = @_;
        $self->depends_on('extract_fltk');
        return _path $self->notes('fltk_dir'), ($extra || '');
    }

    sub archive {
        my ($self, $args) = @_;
        my $arch = $args->{'output'};
        my @cmd = ($self->notes('AR'), $arch,
                   map { _rel($_) } @{$args->{'objects'}}
        );
        print STDERR "@cmd\n" if !$self->quiet;
        return run(@cmd) ? $arch : ();
    }

    sub test_exe {
        my ($self, $args) = @_;
        my ($exe,  @obj)  = $self->build_exe($args);
        return if !$exe;
        my $return = $self->do_system($exe);
        unlink $exe, @obj;
        return $return;
    }

    sub compile {
        my ($self, $args) = @_;
        my $cbuilder = $self->cbuilder;

        #local $^W = 0;
        #local $cbuilder->{'quiet'} = 1;
        if (!$args->{'source'}) {
            (my $FH, $args->{'source'}) = tempfile(
                                     undef, SUFFIX => '.cpp'    #, UNLINK => 1
            );
            syswrite($FH,
                     ($args->{'code'} ?
                          delete $args->{'code'}
                      : 'int main(){return 0;}'
                         )
                         . "\n"
            );
            close $FH;
            $self->add_to_cleanup($args->{'source'});
        }

        #open(my ($OLDERR), ">&STDERR");
        #close *STDERR if $cbuilder->{'quiet'};
        my $obj = eval {
            $cbuilder->compile(
                  ($args->{'source'} !~ m[\.c$] ? ('C++' => 1) : ()),
                  source => $args->{'source'},
                  ($args->{'include_dirs'}
                   ? (include_dirs => $args->{'include_dirs'})
                   : ()
                  ),
                  ($args->{'extra_compiler_flags'}
                   ? (extra_compiler_flags => $args->{'extra_compiler_flags'})
                   : ()
                  )
            );
        };

        #open(*STDERR, '>&', $OLDERR)
        #    || exit !print "Couldn't restore STDERR: $!\n";
        return $obj ? $obj : ();
    }

    sub link_exe {
        my ($self, $args) = @_;
        local $^W = 0;

        #my $cbuilder = ExtUtils::CBuilder->new(config=>{cc => 'cl'});
        my $cbuilder = $self->cbuilder;
        local $cbuilder->{'quiet'} = 1;
        my $exe = eval {
            $cbuilder->link_executable(
                                     objects            => $args->{'objects'},
                                     extra_linker_flags => (
                                         (  $args->{'extra_linker_flags'}
                                          ? $args->{'extra_linker_flags'}
                                          : ''
                                         )
                                         . ($args->{'source'} =~ m[\.c$] ? ''
                                            : ' -lsupc++'
                                         )
                                     )
            );
        };
        return $exe ? $exe : ();
    }

    sub build_exe {
        my ($self, $args) = @_;
        my $obj = $self->compile($args);
        return if !$obj;
        $args->{'objects'} = [$obj];
        my $exe = $self->link_exe($args);
        return if !$exe;
        return ($exe, $obj) if wantarray;
        unlink $obj;
        return $exe;
    }

    sub ACTION_copy_headers {
        my ($self) = @_;
        $self->depends_on('write_config_h');
        $self->depends_on('write_config_yml');
        my $headers_location
            = _path($self->fltk_dir(), $self->notes('headers_path'));
        my $headers_share = _path($self->base_dir(), qw[share include]);
        if (!chdir $headers_location) {
            printf 'Failed to cd to %s to copy headers', $headers_location;
            exit 0;
        }
        find {
            wanted => sub {
                return if -d;
                $self->copy_if_modified(
                                     from => $File::Find::name,
                                     to   => _path(
                                                 $headers_share,
                                                 $self->notes('headers_path'),
                                                 $File::Find::name
                                     )
                );
            },
            no_chdir => 1
            },
            '.';
        if (!chdir _path($self->fltk_dir())) {
            print 'Failed to cd to fltk\'s include directory';
            exit 0;
        }
        $self->copy_if_modified(from => 'config.h',
                                to   => _path($headers_share, 'config.h'));
        print "Copying headers to sharedir...\n" if !$self->quiet;
        if (!chdir $self->base_dir()) {
            printf 'Failed to return to %s', $self->base_dir();
            exit 0;
        }
        $self->notes(headers => $headers_share);
        return 1;
    }

    # Configure
    sub configure {
        my ($self, $args) = @_;
        $self->notes('_a'       => $Config{'_a'});
        $self->notes('ldflags'  => '');
        $self->notes('cxxflags' => '');
        $self->notes('cflags'   => '');
        $self->notes('GL'       => '');
        $self->notes('define'   => {});
        $self->notes(
            'image_flags' => (

                #"-lpng -lfltk2_images -ljpeg -lz"
                $self->notes('branch') eq '1.3.x' ?
                    ' -lfltk_images '
                : ' -lfltk2_images '
            )
        );
        $self->notes('include_dirs' => {});
        $self->notes('lib_dirs'     => {});
        $self->_configure_ar;
        {
            my %sizeof;
            for my $type (qw[short int long]) {
                printf 'Checking size of %s... ', $type;
                my $exe = $self->build_exe({code => <<"" });
static long int longval () { return (long int) (sizeof ($type)); }
static unsigned long int ulongval () { return (long int) (sizeof ($type)); }
#include <stdio.h>
#include <stdlib.h>
int main ( ) {
    if (((long int) (sizeof ($type))) < 0) {
        long int i = longval ();
        if (i != ((long int) (sizeof ($type))))
            return 1;
        printf ("%ld", i);
    }
    else {
        unsigned long int i = ulongval ();
        if (i != ((long int) (sizeof ($type))))
            return 1;
        printf ("%lu", i);
    }
    return 0;
}

                $sizeof{$type} = $exe ? `$exe` : 0;
                print "okay\n";
            }
            #
            if ($sizeof{'short'} == 2) {
                $self->notes('define')->{'U16'} = 'unsigned short';
            }
            if ($sizeof{'int'} == 4) {
                $self->notes('define')->{'U32'} = 'unsigned';
            }
            else {
                $self->notes('define')->{'U32'} = 'unsigned long';
            }
            if ($sizeof{'int'} == 8) {
                $self->notes('define')->{'U64'} = 'unsigned';
            }
            elsif ($sizeof{'long'} == 8) {
                $self->notes('define')->{'U64'} = 'unsigned long';
            }
        }
        {
            print
                'Checking whether the compiler recognizes bool as a built-in type... ';
            my $exe = $self->build_exe({code => <<"" });
#include <stdio.h>
#include <stdlib.h>
int f(int  x){printf ("int "); return 1;}
int f(char x){printf ("char"); return 1;}
int f(bool x){printf ("bool"); return 1;}
int main ( ) {
    bool b = true;
    return f(b);
}

            my $type = $exe ? `$exe` : 0;
            if ($type) { print "yes ($type)\n" }
            else {
                print "no\n";    # But we can pretend...
                $self->notes(  'cxxflags' => $self->notes('cxxflags')
                             . ' -Dbool=char -Dfalse=0 -Dtrue=1 ');
                $self->notes(  'cflags' => $self->notes('cflags')
                             . ' -Dbool=char -Dfalse=0 -Dtrue=1 ');
            }
        }
        if (0 && can_run('sh')) {
            my $cwd = cwd;
            warn _abs cwd;
            if (chdir(_abs $self->fltk_dir())
                && run('sh', './configure'))
            {                    #use Data::Dump;
                my @defines = qw[FLTK_DATADIR FLTK_DOCDIR BORDER_WIDTH
                    USE_X11 USE_QUARTZ __APPLE_QUARTZ__ __APPLE_QD__
                    USE_COLORMAP USE_X11_MULTITHREADING USE_XFT USE_XCURSOR
                    USE_CAIRO USE_CLIPOUT USE_XSHM HAVE_XDBE USE_XDBE HAVE_OVERLAY
                    USE_OVERLAY USE_XINERAMA USE_MULTIMONITOR USE_STOCK_BRUSH
                    USE_XIM HAVE_ICONV HAVE_GL HAVE_GL_GLU_H HAVE_GL_OVERLAY
                    USE_GL_OVERLAY USE_GLEW HAVE_GLXGETPROCADDRESSARB
                    HAVE_DIRENT_H HAVE_STRING_H HAVE_SYS_NDIR_H HAVE_SYS_DIR_H
                    HAVE_NDIR_H HAVE_SCANDIR HAVE_SCANDIR_POSIX HAVE_STRING_H
                    HAVE_STRINGS_H HAVE_VSNPRINTF HAVE_SNPRINTF HAVE_STRCASECMP
                    HAVE_STRDUP HAVE_STRLCAT HAVE_STRLCPY HAVE_STRNCASECMP
                    HAVE_SYS_SELECT_H HAVE_SYS_STDTYPES_H USE_POLL HAVE_LIBPNG
                    HAVE_LIBZ HAVE_LIBJPEG HAVE_LOCAL_PNG_H HAVE_PNG_H
                    HAVE_LIBPNG_PNG_H HAVE_LOCAL_JPEG_H HAVE_PTHREAD
                    HAVE_PTHREAD_H HAVE_EXCEPTIONS HAVE_DLOPEN BOXX_OVERLAY_BUGS
                    SGI320_BUG CLICK_MOVES_FOCUS IGNORE_NUMLOCK
                    USE_PROGRESSIVE_DRAW HAVE_XINERAMA];

                #ddx @defines;
                my $print = '';
                for my $key (@defines) {
                    $print
                        .= '#ifdef '
                        . $key . "\n"
                        . '    printf("'
                        . $key
                        . q[ => '%s'\n,", ]
                        . $key . ");\n"
                        . '#endif // #ifdef '
                        . $key . "\n";
                }

                #print $print;
                my $exe =
                    $self->build_exe({include_dirs => [$self->fltk_dir()],
                                      code         => sprintf <<'', $print});
#include <config.h>
#include <stdio.h>
int main ( ) {
printf("{\n");
%s
printf("};\n");
return 0;
}

                if ($exe) {
                    warn $exe;
                    warn -f $exe;
                    warn system($exe);
                    my $eval = `$exe`;
                    warn `$exe`;
                    die $eval;
                    die 'blah';
                }
                return 1;
            }
        }
        {
            $self->notes('define')->{'FLTK_DATADIR'} = '""';    # unused
            $self->notes('define')->{'FLTK_DOCDIR'}  = '""';    # unused
            $self->notes('define')->{'BORDER_WIDTH'} = 2;       # unused
            $self->notes('define')->{'WORDS_BIGENDIAN'}
                = ((unpack('h*', pack('s', 1)) =~ /01/) ? 1 : 0);    # both
            $self->notes('define')->{'USE_COLORMAP'}           = 1;
            $self->notes('define')->{'USE_X11_MULTITHREADING'} = 0;
            $self->notes('define')->{'USE_XFT'}                = 0;
            $self->notes('define')->{'USE_CAIRO'}
                = ($self->notes('branch') =~ '2.0.x' ? 0 : undef);
            $self->notes('define')->{'USE_CLIPOUT'}      = 0;
            $self->notes('define')->{'USE_XSHM'}         = 0;
            $self->notes('define')->{'HAVE_XDBE'}        = 0;
            $self->notes('define')->{'USE_XDBE'}         = 'HAVE_XDBE';
            $self->notes('define')->{'HAVE_OVERLAY'}     = 0;
            $self->notes('define')->{'USE_OVERLAY'}      = 0;
            $self->notes('define')->{'USE_XINERAMA'}     = 0;
            $self->notes('define')->{'USE_MULTIMONITOR'} = 1;
            $self->notes('define')->{'USE_STOCK_BRUSH'}  = 1;
            $self->notes('define')->{'USE_XIM'}          = 1;
            $self->notes('define')->{'HAVE_ICONV'}       = 0;
            $self->notes('define')->{'HAVE_GL'}
                = $self->assert_lib({headers => ['GL/gl.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_GL_GLU_H'}
                = $self->assert_lib({headers => ['GL/glu.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_GL_OVERLAY'} = 'HAVE_OVERLAY';
            $self->notes('define')->{'USE_GL_OVERLAY'}  = 0;
            $self->notes('define')->{'USE_GLEW'}        = 0;
            $self->notes('define')->{'HAVE_DIRENT_H'}
                = $self->assert_lib({headers => ['dirent.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_STRING_H'}
                = $self->assert_lib({headers => ['string.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_SYS_NDIR_H'}
                = $self->assert_lib({headers => ['sys/ndir.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_SYS_DIR_H'}
                = $self->assert_lib({headers => ['sys/dir.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_NDIR_H'}
                = $self->assert_lib({headers => ['ndir.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_SCANDIR'}       = 1;
            $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = undef;
            $self->notes('define')->{'HAVE_STRING_H'}
                = $self->assert_lib({headers => ['string.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_STRINGS_H'}
                = $self->assert_lib({headers => ['strings.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_VSNPRINTF'}   = 1;
            $self->notes('define')->{'HAVE_SNPRINTF'}    = 1;
            $self->notes('define')->{'HAVE_STRCASECMP'}  = undef;
            $self->notes('define')->{'HAVE_STRDUP'}      = undef;
            $self->notes('define')->{'HAVE_STRLCAT'}     = undef;
            $self->notes('define')->{'HAVE_STRLCPY'}     = undef;
            $self->notes('define')->{'HAVE_STRNCASECMP'} = undef;
            $self->notes('define')->{'HAVE_SYS_SELECT_H'}
                = $self->assert_lib({headers => ['sys/select.h']}) ?
                1
                : undef;
            $self->notes('define')->{'HAVE_SYS_STDTYPES_H'}
                = $self->assert_lib({headers => ['sys/stdtypes.h']}) ?
                1
                : undef;
            $self->notes('define')->{'USE_POLL'} = 0;
            {
                my $png_lib;
                if ($self->assert_lib({libs    => ['png'],
                                       headers => ['libpng/png.h'],
                                       code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
int main ( ) { return png_read_rows( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBPNG'} = 1;
                    $png_lib = ' -lpng ';
                }
                elsif ($self->assert_lib({libs    => ['png'],
                                          headers => ['local/png.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
int main ( ) { return png_read_rows( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBPNG'}      = 1;
                    $self->notes('define')->{'HAVE_LOCAL_PNG_H'} = 1;
                    $png_lib .= ' -lpng ';
                }
                elsif ($self->assert_lib({libs    => ['png'],
                                          headers => ['png.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
int main ( ) { return png_read_rows( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBPNG'} = 1;
                    $png_lib .= ' -lpng ';
                }
                else {
                    $png_lib .= ($self->notes('branch') eq '1.3.x' ?
                                     ' -lfltk_png '
                                 : ' -lfltk2_png '
                    );
                }
                if ($self->assert_lib({libs => ['z'], code => <<''})) {
#ifdef __cplusplus
extern "C"
#endif
char gzopen ();
int main () { return gzopen( ); return 0; }

                    $self->notes('define')->{'HAVE_LIBZ'} = 1;
                    $png_lib .= ' -lz ';
                }
                else {
                    $png_lib .= ($self->notes('branch') eq '1.3.x' ?
                                     ' -lfltk_z '
                                 : ' -lfltk2_z '
                    );
                }
                $self->notes('define')->{'HAVE_PNG_H'} = undef
                    ;  # $self->assert_lib({headers => ['png.h']}) ? 1 : undef
                $self->notes('define')->{'HAVE_LIBPNG_PNG_H'} = undef
                    ; #$self->assert_lib({headers => ['libpng/png.h']}) ? 1 : undef
                      # Add to list
                $self->notes(
                     'image_flags' => $png_lib . $self->notes('image_flags'));
            }
            {
                my $jpeg_lib;
                if ($self->assert_lib({libs    => ['jpeg'],
                                       headers => ['jpeglib.h'],
                                       code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
int main ( ) { return jpeg_destroy_decompress( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBJPEG'} = 1;
                    $jpeg_lib = ' -ljpeg ';
                }
                elsif ($self->assert_lib({libs    => ['jpeg'],
                                          headers => ['local/jpeg.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
int main ( ) { return jpeg_destroy_decompress( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBJPEG'}      = 1;
                    $self->notes('define')->{'HAVE_LOCAL_JPEG_H'} = 1;
                    $jpeg_lib .= ' -ljpeg ';
                }
                elsif ($self->assert_lib({libs    => ['jpeg'],
                                          headers => ['jpeg.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
int main ( ) { return jpeg_destroy_decompress( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBJPEG'} = 1;
                    $jpeg_lib .= ' -ljpeg ';
                }
                else {
                    $jpeg_lib .= ($self->notes('branch') eq '1.3.x' ?
                                      ' -lfltk_jpeg '
                                  : ' -lfltk2_jpeg '
                    );
                }
                if ($self->notes('define')->{'HAVE_LIBZ'}) {
                    $self->notes('image_flags' => $self->notes('image_flags')
                                 . ' -lz');

                    # XXX - Disable building qr[fltk2?_z]?
                }
                else {
       #? ' -lfltk_images -lfltk_png -lfltk_z -lfltk_images -lfltk_jpeg '
       #: ' -lfltk2_images -lfltk2_png -lfltk2_z -lfltk2_images -lfltk2_jpeg '
                    $self->notes('image_flags' => $self->notes('image_flags')
                                     . ($self->notes('branch') eq '1.3.x' ?
                                            ' -lfltk_z'
                                        : ' -lfltk2_z'
                                     )
                    );
                }
                $self->notes('define')->{'HAVE_JPEG_H'} = undef
                    ; # $self->assert_lib({headers => ['jpeg.h']}) ? 1 : undef
                $self->notes('define')->{'HAVE_LIBJPEG_JPEG_H'} = undef
                    ; #$self->assert_lib({headers => ['libjpeg/jpeg.h']}) ? 1 : undef
                      # Add to list
                $self->notes(
                    'image_flags' => $jpeg_lib . $self->notes('image_flags'));
            }
            if ($self->assert_lib(
                               {libs => ['pthread'], headers => ['pthread.h']}
                )
                )
            {   $self->notes('define')->{'HAVE_PTHREAD'}
                    = $self->notes('define')->{'HAVE_PTHREAD_H'} = 1;
            }
            $self->notes('define')->{'HAVE_EXCEPTIONS'}      = undef;
            $self->notes('define')->{'HAVE_DLOPEN'}          = 0;
            $self->notes('define')->{'BOXX_OVERLAY_BUGS'}    = 0;
            $self->notes('define')->{'SGI320_BUG'}           = 0;
            $self->notes('define')->{'CLICK_MOVES_FOCUS'}    = 0;
            $self->notes('define')->{'IGNORE_NUMLOCK'}       = 1;
            $self->notes('define')->{'USE_PROGRESSIVE_DRAW'} = 1;
            $self->notes('define')->{'HAVE_XINERAMA'}        = 0;      # 1.3.x
        }
        {    # Both | All platforms | Standard headers/functions
            my @headers = qw[dirent.h sys/ndir.h sys/dir.h ndir.h];
        HEADER: for my $header (@headers) {
                printf "Checking for %s that defines DIR...\n", $header;
                my $exe = $self->assert_lib(
                               {headers => [$header], code => sprintf <<'' });
#include <stdio.h>
#include <sys/types.h>
int main ( ) {
    if ( ( DIR * ) 0 )
        return 0;
    printf( "1" );
    return 0;
}

                my $define = uc 'HAVE_' . $header;
                $define =~ s|[/\.]|_|g;
                if ($exe) {
                    print "    yes ($header)\n";
                    $self->notes('define')->{$define} = 1;

                    #$self->notes('cache')->{'header_dirent'} = $header;
                    last HEADER;
                }
                else {
                    $self->notes('define')->{$define} = undef;
                    print "no\n";    # But we can pretend...
                }
            }
            #
            $self->notes('define')->{'HAVE_LOCAL_PNG_H'}
                = $self->notes('define')->{'HAVE_LIBPNG'} ? undef : 1;

            #$self->notes('image_flags' => $self->notes('image_flags')
            # -lpng -lfltk2_images -ljpeg -lz
            #
            {
                print 'Checking for library containing pow... ';
                my $_have_pow = '';
            LIB: for my $lib ('', '-lm') {
                    my $exe = $self->build_exe(
                                  {code => <<'', extra_linker_flags => $lib});
#include <stdio.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C"
#endif
char pow ();
int main ( ) {
    printf ("1");
    return pow ();
    return 0;
}

                    if ($exe && `$exe`) {
                        if   ($lib) { print "$lib\n" }
                        else        { print "none required\n" }
                        $self->notes(
                             'ldflags' => $self->notes('ldflags') . " $lib ");
                        $_have_pow = 1;
                        last LIB;
                    }
                }
                if (!$_have_pow) {
                    print "FAIL!\n";    # XXX - quit
                }
            }
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
        }
        return 1;
    }

    sub _configure_ar {
        my $s = shift;
        print 'Locating library archiver... ';
        open(my ($OLDOUT), ">&STDOUT");
        close *STDOUT;
        my ($ar) = grep { run("$_ V") } can_run($Config{'ar'});
        open(*STDOUT, '>&', $OLDOUT)
            || exit !print "Couldn't restore STDOUT: $!\n";
        if (!$ar) {
            print "Could not find the library archiver, aborting.\n";
            exit 0;
        }
        $ar .= ' cr' . (can_run($Config{'ranlib'}) ? 's' : '');
        $s->notes(AR => $ar);
        print "$ar\n";
    }

    sub build_fltk {
        my ($self, $build) = @_;
        $self->quiet(1);
        $self->notes('libs' => []);
        local $self->cbuilder->{'config'}{'archlibexp'} = '---break---';
        if (!chdir $self->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        my $libs = $self->notes('libs_source');
        my @libs = sort { lc $a cmp lc $b }
            grep { !$libs->{$_}{'disabled'} } keys %$libs;

        #printf "The following libs will be built: %s\n", join ', ', @libs;
        for my $lib (@libs) {
            print "Building $lib...\n";
            my $cwd = _abs(_cwd());
            if (!chdir $build->fltk_dir($libs->{$lib}{'directory'})) {
                printf 'Cannot chdir to %s to build %s: %s',
                    $build->fltk_dir($libs->{$lib}{'directory'}),
                    $lib, $!;
                exit 0;
            }
            my @obj;
            my %include_dirs = %{$self->notes('include_dirs')};
            for my $dir (grep { defined $_ } (
                           split(' ', $Config{'incpath'}),
                           $build->fltk_dir(),
                           '..',
                           map { $build->fltk_dir($_) || () } (
                                $self->notes('include_path_compatability'),
                                $self->notes('include_path_images'),
                                $self->notes('include_path_images') . '/zlib/'
                           )
                         )
                )
            {   $include_dirs{_rel(_realpath($dir))}++;
            }

            #use Data::Dump;
            #ddx \%include_dirs;
            #die;
            for my $src (sort { lc $a cmp lc $b } @{$libs->{$lib}{'source'}})
            {   my $obj = _o($src);
                $obj
                    = $build->up_to_date($src, $obj) ?
                    $obj
                    : sub {
                    print "Compiling $src...\n";
                    return $self->compile(
                        {source               => $src,
                         include_dirs         => [keys %include_dirs],
                         extra_compiler_flags => join(
                             ' ',
                             $Config{'ccflags'},
                             '-MD',
                             ($src =~ m[\.c$] ?
                                  $self->notes('cflags')
                              : $self->notes('cxxflags')
                             ),
                             '-DFL_LIBRARY',    # fltk 1.3.x
                         ),
                         output => $obj,
                        }
                    );
                    }
                    ->();
                if (!$obj) {
                    printf 'Failed to compile %s', $src;
                    exit 0;
                }
                push @obj, _abs($obj);
            }
            if (!chdir $cwd) {
                printf 'Cannot chdir to %s after building %s: %s', $cwd, $lib,
                    $!;
                exit 0;
            }
            my $_lib = _rel($build->fltk_dir('lib/' . _a($lib)));
            printf 'Archiving %s... ', $lib;
            $_lib
                = $build->up_to_date(\@obj, $_lib) ?
                $_lib
                : $self->archive({output  => _abs($_lib),
                                  objects => \@obj
                                 }
                );
            if (!$_lib) {
                printf 'Failed to create %s library', $lib;
                exit 0;
            }
            push @{$self->notes('libs')}, $_lib;
            print "done\n";
        }
        if (!chdir $build->fltk_dir()) {
            print 'Failed to cd to ' . $self->fltk_dir() . ' to return home';
            exit 0;
        }
        return scalar @{$self->notes('libs')};
    }

    # Module::Build actions
    sub ACTION_fetch_fltk {
        my ($self, %args) = @_;
        my ($dir, $archive, $extention);
        $args{'to'} = (defined $args{'to'} ?
                           $args{'to'}
                       : $self->notes('snapshot_dir')
        );
        unshift @INC, (_path($self->base_dir, 'lib'));
        if (   (!$args{'no-git'})
            && (eval 'require ' . $self->module_name)
            && ($self->module_name->can('_git_rev'))
            && ($self->module_name->_git_rev()))
        {   {
                $args{'ext'} ||= [qw[tar.gz zip]];
                my ($file) = grep {-f} map {
                    (sprintf '%s/fltk-%s-r%s.%s',
                     $args{'to'}, $self->notes('branch'),
                     $self->notes('svn'), $_
                        )
                } @{$args{'ext'}};
                if (defined $file) {
                    $self->notes('snapshot_path' => $file);
                    $self->notes('snapshot_dir'  => $args{'to'});
                    return 1;    # $self->depends_on('verify_snapshot');
                }
            }
            my @mirrors = map {
                sprintf '%ssanko-fltk-%s-%s.', $_, $self->notes('branch'),
                    $self->module_name->_git_rev()
            } values %{$self->_snapshot_mirrors()};
            require File::Fetch;
            $File::Fetch::TIMEOUT = $File::Fetch::TIMEOUT = 45;    # Be quick
            printf 'Fetching git snapshot %s... ',
                $self->module_name->_git_rev();
            my ($exts) = ($args{'ext'});
            my ($attempt, $total) = (0, scalar(@$exts) * scalar(@mirrors));
        GIT_MIRROR: for my $mirror (@mirrors) {

                for my $ext (@$exts) {
                    printf "\n[%d/%d] Trying %s%s... ", ++$attempt, $total,
                        $mirror, $ext;
                    my $ff = File::Fetch->new(uri => $mirror . $ext);
                    $archive = $ff->fetch(to => $args{'to'});
                    if ($archive and -f $archive) {
                        $self->notes('snapshot_mirror_uri'      => $ff->uri);
                        $self->notes('snapshot_mirror_location' => $mirror);
                        my $_archive = $archive;
                        $archive = (sprintf '%s/fltk-%s-r%s.%s',
                                    $args{'to'},
                                    $self->notes('branch'),
                                    $self->notes('svn'),
                                    $ext
                        );
                        rename $_archive, $archive;
                        $extention = $ext;
                        $dir       = $args{'to'};
                        last GIT_MIRROR;
                    }
                }
            }
            {
                $args{'ext'} ||= [qw[tar.gz zip]];
                my ($file) = grep {-f} map {
                    (sprintf '%s/fltk-%s-%s.%s',
                     $args{'to'}, $self->notes('branch'),
                     $self->notes('svn'), $_
                        )
                } @{$args{'ext'}};

                #return 1 if defined $file;
            }
        }
        else {    # SVN
            $args{'ext'}    ||= [qw[gz bz2]];
            $args{'scheme'} ||= [qw[http ftp]];
            {
                my ($file) = grep {-f} map {
                    (sprintf '%s/fltk-%s-r%d.tar.%s',
                     $args{'to'}, $self->notes('branch'),
                     $self->notes('svn'), $_
                        )
                } @{$args{'ext'}};
                if (defined $file) {
                    $self->notes('snapshot_path' => $file);
                    $self->notes('snapshot_dir'  => $args{'to'});
                    return $self->depends_on('verify_snapshot');
                }
            }
            require File::Fetch;
            $File::Fetch::TIMEOUT = $File::Fetch::TIMEOUT = 45;    # Be quick
            printf "Fetching SVN snapshot %d... ", $self->notes('svn');
            my ($schemes, $exts, $mirrors)
                = ($args{'scheme'}, $args{'ext'}, $self->_snapshot_mirrors());
            my ($attempt, $total)
                = (
                0, scalar(@$schemes) * scalar(@$exts) * scalar(keys %$mirrors)
                );
            my @mirrors = keys %$mirrors;
            {    # F-Y shuffle
                my $i = @mirrors;
                while (--$i) {
                    my $j = int rand($i + 1);
                    @mirrors[$i, $j] = @mirrors[$j, $i];
                }
            }
        SVN_MIRROR: for my $mirror (@mirrors) {
            EXT: for my $ext (@$exts) {
                SCHEME: for my $scheme (@$schemes) {
                        printf "\n[%d/%d] Trying %s mirror based in %s... ",
                            ++$attempt, $total, uc $scheme, $mirror;
                        my $ff =
                            File::Fetch->new(
                              uri => sprintf
                                  '%s://%s/fltk/snapshots/fltk-%s-r%d.tar.%s',
                              $scheme, $mirrors->{$mirror},
                              $self->notes('branch'),
                              $self->notes('svn'), $ext
                            );
                        $archive = $ff->fetch(to => $args{'to'});
                        if ($archive and -f $archive) {
                            $self->notes('snapshot_mirror_uri' => $ff->uri);
                            $self->notes(
                                       'snapshot_mirror_location' => $mirror);
                            $archive = (sprintf '%s/fltk-%s-r%d.tar.%s',
                                        $args{'to'},
                                        $self->notes('branch'),
                                        $self->notes('svn'),
                                        $ext
                            );
                            $extention = $ext;
                            $dir       = $args{'to'};
                            last SVN_MIRROR;
                        }
                    }
                }
            }
            if (!$archive) {    # bad news
                my (@urls, $i);
                for my $ext (@$exts) {
                    for my $mirror (sort values %$mirrors) {
                        for my $scheme (@$schemes) {
                            push @urls,
                                sprintf
                                '[%d] %s://%s/fltk/snapshots/fltk-%s-r%d.tar.%s',
                                ++$i, $scheme, $mirror,
                                $self->notes('branch'),
                                $self->notes('svn'), $ext;
                        }
                    }
                }
                my $urls = join "\n", @urls;
                $self->_error(
                        {stage => 'fltk source download',
                         fatal => 1,
                         message =>
                             sprintf
                             <<'END', ($self->notes('snapshot_dir')), $urls});
Okay, we just failed at life.

If you want, you may manually download a snapshot and place it in
    %s

Please, use one of the following mirrors:
%s

Exiting...
END
            }
        }
        shift @INC;
        print "done.\n";
        $self->notes('snapshot_dir'  => $args{'to'});
        $self->notes('snapshot_path' => $archive);
        $self->notes('snapshot_dir'  => $dir);       # Unused but good to know
             #$self->add_to_cleanup($dir);
        $self->depends_on('verify_snapshot');
    }

    sub _snapshot_mirrors {
        my $self = shift;
        unshift @INC, (_path($self->base_dir, 'lib'));
        my $return;
        $return
            = eval 'require '
            . $self->module_name
            && $self->module_name->can('_snapshot_mirrors')
            ?
            $self->module_name->_snapshot_mirrors()
            : {
            'California, USA' => 'ftp.easysw.com/pub',
            'New Jersey, USA' => 'ftp2.easysw.com/pub',
            'Espoo, Finland' => 'ftp.funet.fi/pub/mirrors/ftp.easysw.com/pub',
            'Braunschweig, Germany' =>
                'ftp.rz.tu-bs.de/pub/mirror/ftp.easysw.com/ftp/pub'
            };
        shift @INC;
        return $return if $return;
    }

    sub ACTION_verify_snapshot {
        my ($self) = @_;
        return 1 if $self->notes('snapshot_okay');
        require Digest::MD5;
        print 'Checking MD5 hash of archive... ';
        my $archive = $self->notes('snapshot_path');
        my ($ext) = $archive =~ m[([^\.]+)$];
        my $FH;
        if (!open($FH, '<', $archive)) {
            $self->_error(
                 {stage   => 'fltk source validation',
                  fatal   => 1,
                  message => "Can't open '$archive' to check MD5 checksum: $!"
                 }
            );    # XXX - Should I delete the archive and retry?
        }
        binmode($FH);
        unshift @INC, (_path($self->base_dir, 'lib'));
        if (eval 'require ' . $self->module_name) {
            my $md5 = $self->module_name->_md5;
            if (Digest::MD5->new->addfile($FH)->hexdigest eq $md5->{$ext}) {
                print "MD5 checksum is okay\n";
                $self->notes('snapshot_okay' => 'Valid @ ' . time);
                return 1;
            }
        }
        else {
            print "Cannot find checksum. Hope this works out...\n";
            $self->notes('snapshot_okay' => 'Pray that it is... @' . time);
            return 1;
        }
        shift @INC;
        close $FH;
        if ($self->notes('bad_fetch_retry')->{'count'}++ > 10) {
            $self->_error(
                {stage => 'fltk source validation',
                 fatal => 1,
                 message =>
                     'Found/downloaded archive failed to match MD5 checksum... Giving up.'
                }
            );
        }
        $self->_error(
            {stage => 'fltk source validation',
             fatal => 0,
             message =>
                 'Found/downloaded archive failed to match MD5 checksum... Retrying.'
            }
        );
        $self->dispatch('fetch_fltk');
    }

    sub ACTION_extract_fltk {
        my ($self, %args) = @_;
        local @INC = ('lib', @INC);
        unshift @INC, (_path($self->base_dir, 'lib'));
        eval 'require ' . $self->module_name;
        my $key = $self->module_name->can('_git_rev') ? 'sanko-' : '';
        $self->depends_on('fetch_fltk');
        $args{'from'} ||= $self->notes('snapshot_path');
        $args{'to'}   ||= _rel(($self->notes('extract_dir')));
        if (!( defined($self->notes('fltk_dir'))
               && -d $args{'to'} . sprintf '/%sfltk-%s-%s',
               $key,
               $self->notes('branch'),
               $key && $self->module_name->can('_git_rev')
               ?
               $self->module_name->_git_rev()
               : 'r' . $self->notes('svn')
            )
            )
        {   printf 'Extracting snapshot from %s to %s... ',
                _rel($args{'from'}),
                _rel($args{'to'});
            require Archive::Extract;
            my $ae = Archive::Extract->new(archive => $args{'from'});
            if (!$ae->extract(to => $args{'to'})) {
                $self->_error({stage   => 'fltk source extraction',
                               fatal   => 1,
                               message => $ae->error
                              }
                );
            }
            $self->add_to_cleanup($ae->extract_path);
            $self->notes('timestamp_extracted' => time);
            $self->notes('extract'             => $args{'to'});
            $self->notes('snapshot_path'       => $args{'from'});
            $self->notes('fltk_patched'        => 0);
            $self->notes(
                     'fltk_dir' => _abs $args{'to'} . sprintf '/%sfltk-%s-%s',
                     $key,
                     $self->notes('branch'),
                     $key ?
                         $self->module_name->_git_rev()
                     : 'r' . $self->notes('svn')
            );
            print "done.\n";
        }
        return 1;
    }

    sub ACTION_configure {
        my ($self) = @_;
        if (!$self->notes('timestamp_configure')

            #   || !$self->notes('define')
            #|| !-f $self->fltk_dir('config.h')
            )
        {   print "Gathering configuration data...\n";
            $self->configure();
            $self->notes(timestamp_configure => time);
        }
        return 1;
    }

    sub ACTION_write_config_h {
        my ($self) = @_;

        #return 1
        #    if -f $self->notes('config_yml')
        #        && -s $self->notes('config_yml');
        $self->depends_on('configure');
        $self->depends_on('extract_fltk');
        if (!chdir $self->fltk_dir()) {
            print 'Failed to cd to '
                . $self->fltk_dir()
                . ' to find config.h';
            exit 0;
        }
        if (   (!-f 'config.h')
            || (!$self->notes('timestamp_config_h'))
            || ($self->notes('timestamp_configure')
                > $self->notes('timestamp_config_h'))
            )
        {   {
                print 'Creating config.h... ';
                my $config = '';
                my %config = %{$self->notes('define')};
                for my $key (
                    sort {
                        $config{$a} && $config{$a} =~ m[^HAVE_] ?
                            ($b cmp $a)
                            : ($a cmp $b)
                    } keys %config
                    )
                {   $config .=
                        sprintf((defined $config{$key} ?
                                     '#define %-25s %s'
                                 : '#undef  %-35s'
                                )
                                . "\n",
                                $key,
                                $config{$key}
                        );
                }
                $config .= "\n";
                open(my $CONFIG_H, '>', 'config.h')
                    || Carp::confess 'Failed to open config.h ';
                syswrite($CONFIG_H, $config) == length($config)
                    || Carp::confess 'Failed to write config.h';
                close $CONFIG_H;
                $self->notes(timestamp_config_h => time);
                print "okay\n";
            }
        }
        if (!chdir $self->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        return 1;
    }

    sub ACTION_write_config_yml {
        my ($self) = @_;
        $self->depends_on('configure');
        require YAML::Tiny;
        printf 'Updating %s config... ', $self->module_name;
        my $me        = ($self->notes('config_yml'));
        my $mode_orig = 0644;
        if (!-d _dir($me)) {
            require File::Path;
            $self->add_to_cleanup(File::Path::make_path(_dir($me)));
        }
        elsif (-d $me) {
            $mode_orig = (stat $me)[2] & 07777;
            chmod($mode_orig | 0222, $me);    # Make it writeable
        }
        open(my ($YML), '>', $me)
            || $self->_error({stage   => 'config.yml creation',
                              fatal   => 1,
                              message => sprintf 'Failed to open %s: %s',
                              $me, $!
                             }
            );
        syswrite($YML, YAML::Tiny::Dump(\%{$self->notes()}))
            || $self->_error(
                         {stage   => 'config.yml creation',
                          fatal   => 1,
                          message => sprintf 'Failed to write data to %s: %s',
                          $me, $!
                         }
            );
        chmod($mode_orig, $me)
            || $self->_error(
                   {stage   => 'config.yml creation',
                    fatal   => 0,
                    message => sprintf 'Cannot restore permissions on %s: %s',
                    $me, $!
                   }
            );
        print "okay\n";
    }

    sub ACTION_reset_config {
        my ($self) = @_;
        return if !$self->notes('timestamp_configure');
        printf 'Cleaning %s config... ', $self->module_name();
        my $yml = $self->notes('config_yml');
        if (-f $yml) {
            my $mode_orig = (stat $yml)[2] & 07777;
            chmod($mode_orig | 0222, $yml);    # Make it writeable
            unlink $yml;
        }
        $self->notes(timestamp_configure => 0);
        $self->notes(timestamp_extracted => 0);
        print "done\n";
    }

    sub ACTION_build_fltk {
        my ($self) = @_;
        $self->depends_on('write_config_h');
        $self->depends_on('write_config_yml');
        $self->depends_on('patch_fltk');
        my @lib = $self->build_fltk($self);
        if (!chdir $self->base_dir()) {
            printf 'Failed to return to %s to copy libs', $self->base_dir();
            exit 0;
        }
        for my $lib (@{$self->notes('libs')}) {
            $self->copy_if_modified(
                   from => $lib,
                   to => _path($self->base_dir(), qw[share libs], _file($lib))
            );
        }
        return 1;
    }

    sub ACTION_code {
        my ($self) = @_;
        $self->depends_on(qw[build_fltk copy_headers]);
        return $self->SUPER::ACTION_code;
    }

    sub _error {
        my ($self, $error) = @_;
        $error->{'fatal'} = defined $error->{'fatal'} ? $error->{'fatal'} : 0;
        my $msg = $error->{'message'};
        $msg =~ s|(.+)|  $1|gm;
        printf "\nWARNING: %s error enountered during %s:\n%s\n",
            ($error->{'fatal'} ? ('*** Fatal') : 'Non-fatal'),
            $error->{'stage'}, $msg, '-- ' x 10;
        if ($error->{'fatal'}) {
            printf STDOUT ('*** ' x 15) . "\n"
                . 'error was encountered during the build process . '
                . "Please correct it and run Build.PL again.\nExiting...",
                exit defined $error->{'exit'} ? $error->{'exit'} : 0;
        }
    }

    sub ACTION_clean {
        my $self = shift;
        $self->dispatch('reset_config');
        $self->SUPER::ACTION_clean(@_);
        $self->notes(errors => []);    # Reset fatal and non-fatal errors
    }
    {
        # Ganked from Devel::CheckLib
        sub assert_lib {
            my ($self, $args) = @_;

            # Defaults
            $args->{'code'}         ||= "int main( ) { return 0; }\n";
            $args->{'include_dirs'} ||= ();
            $args->{'lib_dirs'}     ||= ();
            $args->{'headers'}      ||= ();
            $args->{'libs'}         ||= ();

            #use Data::Dumper;
            #warn Dumper $args;
            # first figure out which headers we can' t find...
        HEADER: for my $header (@{$args->{'headers'}}) {

                #printf 'Trying to compile with %s... ', $header;
                push @{$args->{'include_dirs'}}, $self->find_h($header);
                if ($self->compile(
                        {code => "#include <$header>\n" . $args->{'code'},
                         include_dirs => [

                             #$self->find_h($header),
                             @{$args->{'include_dirs'}},
                             keys %{$self->notes('include_dirs')}
                         ],
                         lib_dirs => [grep {defined} $args->{'lib_dirs'},
                                      keys %{$self->notes('lib_dirs')}
                         ]
                        }
                    )
                    )
                {   print "okay\n";
                    next;
                }
                else {
                    print "Cannot include $header\n";
                    return 0;
                }
            }

            # now do each library in turn with no headers
            for my $lib (@{$args->{'libs'}}) {

                #printf 'Trying to link with %s... ', $lib;
                if ($self->test_exe(
                           {code =>
                                join("\n",
                                (map {"#include <$_>"} @{$args->{'headers'}}),
                                $args->{'code'}),
                            include_dirs => [
                                          ($args->{'include_dirs'}
                                           ?
                                               @{$args->{'include_dirs'}}
                                           : ()
                                          ),
                                          keys %{$self->notes('include_dirs')}
                            ],
                            lib_dirs => [grep {defined} $args->{'lib_dirs'},
                                         keys %{$self->notes('lib_dirs')},
                                         $self->find_lib($lib)
                            ],
                            extra_linker_flags => "-l$lib"
                           }
                    )
                    )
                {   print "okay\n";
                    next;
                }
                print "Cannot link $lib ";
                return 0;
            }
            return 1;
        }

        sub find_lib {
            my ($self, $find, $dir) = @_;
            printf 'Looking for lib%s... ', $find;
            require File::Find::Rule;
            $find =~ s[([\+\*\.])][\\$1]g;
            $dir ||= $Config{'libpth'};
            $dir = _path($dir);
            my @files
                = File::Find::Rule->file()
                ->name('lib' . $find . $Config{'_a'})->maxdepth(1)
                ->in(split ' ', $dir);
            if (@files) {
                printf "found in %s\n", _dir($files[0]);
                $self->notes('lib_dirs')->{_path((_dir($files[0])))}++;
                return _path((_dir($files[0])));
            }
            print "missing\n";
            return ();
        }

        sub find_h {
            my ($self, $file, $dir) = @_;
            printf 'Looking for %s... ', $file;
            $dir = join ' ', ($dir || ''), $Config{'incpath'},
                $Config{'usrinc'};
            {    # work around bug in recent Strawberry perl
                my @pth = split ' ', $Config{'libpth'};
                s[lib$][include] for @pth;
                $dir .= join ' ', @pth;
            }
            $dir =~ s|\s+| |g;
            for my $test (split m[\s+]m, $dir) {
                if (-e _path($test . '/' . $file)) {
                    printf "found in %s\n", _path($test);
                    $self->notes('include_dirs')->{_path($test)}++;
                    return _path($test);
                }
            }
            print "missing\n";
            return ();
        }

        sub _find_h {
            my ($self, $file, $dir) = @_;
            printf 'Looking for %s... ', $file;
            require File::Find::Rule;
            $dir ||= $Config{'incpath'} . ' ' . $Config{'usrinc'};
            $dir  = _path($dir);
            $file = _path($file);
            my @files = File::Find::Rule->file()->name($file)->maxdepth(1)
                ->in(split ' ', $dir);
            if (@files) {
                printf "found in %s\n", _dir($files[0]);
                $self->notes('include_dirs')->{_dir($files[0])}++;
                return _dir($files[0]);
            }
            print "missing\n";
            return ();
        }
    }

    # Patch system
    sub ACTION_patch_fltk {
        my $s = shift;
        return if $s->notes('fltk_patched');
        my $cwd = _abs(_cwd());
        if (!chdir $s->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        my @patches = $s->fltk_patches;
        printf "Patching FLTK... (expect %d patch%s)\n", scalar(@patches),
            (@patches == 1 ? '' : 'es');
        for my $patch (@patches) {
            printf 'Applying %s... ', _rel($patch);
            printf ucfirst "%sokay\n",
                $s->_patch_dir($s->fltk_dir, $s->_parse_diff($patch))
                ? [$s->notes('fltk_patched', gmtime()), '']->[1]
                : [$s->notes('fltk_patched', 0), 'not ']->[1];
        }
    }

    sub _parse_diff {    # Takes unified diff and returns list of changes
        my ($s, $diff) = @_;
        if (!chdir $s->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        $diff = sub {
            open my $FH, '<', shift || return;
            sysread $FH, my $DAT, -s $FH;
            $DAT;
            }
            ->($diff) || $diff if $diff !~ m[\r?\n] && -f $diff;
        my @diff = split /^/m, $diff;
        my $eol = $diff[-1] =~ m[(\r?\n)$];

        #
        my (%patch, $hunk, $from_file, $to_file, $from_time, $to_time);
        while (my $line = shift @diff) {
            if ($line =~ m[^\@\@\s+-([\d+,?]+)\s+\+([\d+,?]+)\s+\@\@\s*$])
            {    # Unified
                if ($hunk) {
                    push @{$patch{$to_file}{hunks}}, $hunk;
                    $hunk = ();
                }
                ($hunk->{from_pos}, $hunk->{from_len}) = split ',', $1;
                ($hunk->{to_pos},   $hunk->{to_len})   = split ',', $2;
                $hunk->{$_}-- for qw[from_pos to_pos];
            }
            elsif ($line =~ m[^---\s+([^\t]+)\t(.+)$]) {
                ($from_file, $from_time) = ($1, $2);
            }
            elsif ($line =~ m[^\+\+\+\s+([^\t]+)\t(.+)$]) {
                ($to_file, $to_time) = ($1, $2);
            }
            else {
                next if !$hunk;
                ($hunk->{from_file}, $hunk->{to_file},
                 $hunk->{from_time}, $hunk->{to_time}
                ) = ($from_file, $to_file, $from_time, $to_time);
                push @{$hunk->{data}}, $line;
            }
        }

        #
        push @{$patch{$to_file}{hunks}}, $hunk;
        return \%patch;
    }

    sub _patch_dir {
        my ($s, $dir, $patches) = @_;
        if (!chdir $s->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        my $tally;
        require File::Spec;
        for my $file (keys %$patches) {
            my $abs = File::Spec->catfile($dir, $file);
            my $orig;
            {
                open(my $FH, '<', _abs($abs))
                    || die 'Failed to open '
                    . _abs($abs)
                    . ' for patching | '
                    . $!;
                sysread($FH, $orig, -s $FH) == -s $FH
                    || die 'Failed to slurp ' . _abs($abs) . ' | ' . $!;
                close $FH;
            }
            my @orig = split /^/m, $orig;
            my $data = $s->_patch_data(\@orig, $patches->{$file}{'hunks'});
            $tally += sub {
                open my $FH, '>', shift || return;
                syswrite $FH, shift;
                }
                ->($abs, join '', @$data) if $data;
        }
        return $tally;
    }

    sub _patch_data {
        my ($s, $text, $hunks) = @_;
        if (!chdir $s->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        for my $hunk (reverse @$hunks) {
            my @pdata;
            my $num = $hunk->{from_pos};
            for (@{$hunk->{data}}) {
                my ($first, $line) = (m[^([ \-\+])(.*)$]s) or next;
                if ($first ne '+') {
                    my ($orig)   = ($text->[$num++] =~ m[^(.+?)(\r\n|\n)$]);
                    my ($expect) = ($line           =~ m[^(.+?)(\r\n|\n)$]);
                    next if !$orig || !$expect;
                    return !
                        printf
                        <<'END', $num, $orig, $expect if $orig ne $expect
Files differ at line %d!
    Expected: %s
    Actual:   %s
END
                }
                next if $first eq '-';
                push @pdata, $line;
            }
            splice @$text, $hunk->{from_pos}, $hunk->{from_len}, @pdata;
        }
        return $text;
    }

    sub fltk_patches {
        my $s = shift;
        my $toolkit
            = $^O eq 'MSWin32' ? 'win32'
            : $^O eq 'darwin'  ? 'darwin'
            :                    'unix';
        my @patches;
        find {
            wanted => sub {
                return if -d;
                return if !m[$toolkit];
                push @patches, $File::Find::name;
            },
            no_chdir => 1
            },
            $s->base_dir() . '/patches';
        @patches;
    }
    1;
}

=pod

=head1 FLTK 1.3.x Configuration Options

=head2 C<BORDER_WIDTH>

Thickness of C<FL_UP_BOX> and C<FL_DOWN_BOX>.  Current C<1,2,> and C<3> are
supported.

  3 is the historic FLTK look.
  2 is the default and looks (nothing) like Microsoft Windows, KDE, and Qt.
  1 is a plausible future evolution...

Note that this may be simulated at runtime by redefining the boxtypes using
C<Fl::set_boxtype()>.

=head1 FLTK 2.0.x Configuration Options

TODO

=cut
