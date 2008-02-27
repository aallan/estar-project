
#+ 
#  Name:
#    user_agent.csh

#  Purposes:
#     Sets aliases for eSTAR User Agent startup

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR_DIR/etc/user_agent.csh

#  Description:
#    Sets all the aliases required to run the eSTAR User Agent

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  History:
#     $Log: user_agent.csh,v $
#     Revision 1.3  2008/02/27 12:43:10  aa
#     Modified for move to estar5
#
#     Revision 1.2  2006/05/14 17:27:34  aa
#     Modifications to work on OSX, removed killfam. Fixed gcn_server.pl so that it fires on BAT positions
#
#     Revision 1.1  2004/11/30 19:05:31  aa
#     Working user_agent.pl, Handler.pm cleaned of most $main:: references. Only $main::OPT{http_agent} reference remains, similar to jach_agent.pl. Not tried a loopback test yet
#
#     Revision 1.2  2003/05/08 20:20:46  aa
#     Added Buster Agent, fixed bug in eSTAR::SOAP::User
#
#     Revision 1.1  2003/04/29 17:37:20  aa
#     Intial agent infrastructure, options and state file, some logging implemented
#
#     Revision 1.1  2002/03/22 21:53:35  aa
#     Skeleton Infrastructure for Intelligent Agent GUI
#

#  Revision:
#     $Id: user_agent.csh,v 1.3 2008/02/27 12:43:10 aa Exp $

#  Copyright:
#     Copyright (C) 2003 University of Exeter. All Rights Reserved.

#-

# Set up back door for the version number

if ($?ESTAR_VERSION) then
  set pkgvers = $ESTAR_VERSION
  echo "ESTAR_VERSION = ${ESTAR_VERSION}"
else
  set pkgvers = 3.0
endif

# Need to make sure we use the right PERL (v5.8.0)

# Check for the existence of a $ESTAR2_PERLBIN environment variable and
# allow that to be used in preference to the starlink version if set.

if ($?ESTAR_PERLBIN) then
  setenv PERL $ESTAR_PERLBIN
  echo " "
  echo "ESTAR_PERLBIN = ${ESTAR_PERLBIN}"
else
  setenv PERL NONE
endif

# set PGPLOT_DIR to point to the modified version of PGPLOT
#if ($?ESTAR_TKPGPLOT) then
#  setenv PGPLOT_DIR $ESTAR_TKPGPLOT
#  echo "ESTAR_TKPGPLOT = ${ESTAR_TKPGPLOT}"
#else
#  echo " "
#  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
#  echo "PGPLOT could not be found, please install PGPLOT 5.2.2" 
#  echo "patched for use of the /PTK driver (uses Tk::Pgplot 0.30)" 
#  exit
#endif
      
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
  echo "Starting User Agent (${ia_args} )"
  ${PERL} ${ESTAR_DIR}/bin/user_agent.pl ${ia_args}

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
