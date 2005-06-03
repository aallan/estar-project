
#+ 
#  Name:
#    correlation_daemon.csh

#  Purposes:
#     Sets aliases for eSTAR JACH Correlation Daemon startup

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR_DIR/etc/correlation_daemon.csh

#  Description:
#    Sets all the aliases required to run the eSTAR JACH Embedded Agent

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  History:
#     $Log: correlation_daemon.csh,v $
#     Revision 1.3  2005/06/03 02:34:00  cavanagh
#     sort of working...
#
#     Revision 1.2  2005/06/03 02:24:08  cavanagh
#     spawn off four processes, one for each WFCAM camera
#
#     Revision 1.1  2005/06/02 00:10:04  aa
#     Added a startup script for the correlation daemon
#

#  Revision:
#     $Id: correlation_daemon.csh,v 1.3 2005/06/03 02:34:00 cavanagh Exp $

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

source /star/etc/cshrc
source /star/etc/login

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
  echo "Starting JACH Correlation Daemon (${ia_args} )"
  ${PERL} ${ESTAR_DIR}/bin/correlation_daemon.pl -camera 1 ${ia_args} &
#  ${PERL} ${ESTAR_DIR}/bin/correlation_daemon.pl -camera 2 ${ia_args} &
#  ${PERL} ${ESTAR_DIR}/bin/correlation_daemon.pl -camera 3 ${ia_args} &
#  ${PERL} ${ESTAR_DIR}/bin/correlation_daemon.pl -camera 4 ${ia_args} &

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
