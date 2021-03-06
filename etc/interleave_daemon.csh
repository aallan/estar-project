
#+ 
#  Name:
#    interleave_daemon.csh

#  Purposes:
#     Sets aliases for eSTAR JACH Interleave Correlation Daemon startup

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR_DIR/etc/interleave_daemon.csh

#  Description:
#    Sets all the aliases required to run the eSTAR JACH Embedded Agent

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  History:
#     $Log: interleave_daemon.csh,v $
#     Revision 1.1  2005/07/01 20:51:38  aa
#     Added startup script
#

#  Revision:
#     $Id: interleave_daemon.csh,v 1.1 2005/07/01 20:51:38 aa Exp $

#  Copyright:
#     Copyright (C) 2003 University of Exeter. All Rights Reserved.

#-

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
  setenv ESTAR_PERL5LIB ${ESTAR_DIR}/lib/perl5
  echo " "
  echo "ESTAR_PERL5LIB = ${ESTAR_PERL5LIB} (Warning)"
endif

if ($?STARLINK) then
   source ${STARLINK}/etc/cshrc
   source ${STARLINK}/etc/login
else
   echo "STARLINK not defined. May be unable to find CCDPACK"
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
  echo "Starting JACH Interleave Correlation Daemon (${ia_args} )"
  ${PERL} ${ESTAR_DIR}/bin/interleave_daemon.pl -camera 1 ${ia_args} &
#  ${PERL} ${ESTAR_DIR}/bin/interleave_daemon.pl -camera 2 ${ia_args} &
#  ${PERL} ${ESTAR_DIR}/bin/interleave_daemon.pl -camera 3 ${ia_args} &
#  ${PERL} ${ESTAR_DIR}/bin/interleave_daemon.pl -camera 4 ${ia_args} &

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
