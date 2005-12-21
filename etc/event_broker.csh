
# Need to make sure we use the right PERL (v5.8.0)

# Check for the existence of a $ESTAR_PERLBIN environment variable and
# allow that to be used in preference to the starlink version if set.

if ($?ESTAR_PERLBIN) then
  setenv PERL $ESTAR_PERLBIN
  echo " "
  echo "ESTAR_PERLBIN = ${ESTAR_PERLBIN}"
else
  setenv PERL NONE
endif
      
# Set up back door for the version number

if ($?ESTAR_VERSION) then
  set pkgvers = $ESTAR_VERSION
  echo "ESTAR_VERSION = ${ESTAR_VERSION}"
else
  set pkgvers = 3.0
endif

# Default for ESTAR_PERL5LIB

if (! $?ESTAR_PERL5LIB) then
  setenv ESTAR_PERl5LIB ${ESTAR_DIR}/lib/perl5
  echo " "
  echo "ESTAR_PERL5LIB = ${ESTAR_PERl5LIB} (Warning)"
endif

# These are perl programs

if (-e $PERL ) then

  # pass through command line arguements
  set args = ($argv[1-])
  set ia_args = ""
  if ( $#args > 0  ) then
    while ( $#args > 0 )
       set ia_args = "${ia_args} $args[1]"
       shift args       
    end
  endif

  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version ${pkgvers})"
  echo "--------------------------------"
  echo "Please wait..."
  echo "Starting EVENT BROKER SERVER (${ia_args} )"
  ${PERL} ${ESTAR_DIR}/bin/event_broker.pl ${ia_args}

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
