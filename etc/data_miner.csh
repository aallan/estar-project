
#+ 
#  Name:
#    data_miner.csh

#  Purposes:
#     Start the eSTAR Data Mining Process

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR3_DIR/etc/wfcam_agent.csh

#  Description:
#    Sets all the aliases required to run the eSTAR Data Miner, passes
#    command line arguements to the perl application.

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  History:
#     $Log: data_miner.csh,v $
#     Revision 1.1  2004/02/20 00:59:41  aa
#     Added a skeleton data mining process, it has a SOAP server on port 8006
#
#     Revision 1.2  2004/02/19 23:33:54  aa

#  Revision:
#     $Id: data_miner.csh,v 1.1 2004/02/20 00:59:41 aa Exp $

#  Copyright:
#     Copyright (C) 2003 University of Exeter. All Rights Reserved.

#-

# Need to make sure we use the right PERL (v5.8.3)

# Check for the existence of a $ESTAR3_PERLBIN environment variable and
# allow that to be used in preference to the starlink version if set.

if ($?ESTAR3_PERLBIN) then
  setenv PERL $ESTAR3_PERLBIN
  echo " "
  echo "ESTAR3_PERLBIN = ${ESTAR3_PERLBIN}"
else
  setenv PERL NONE
endif

# set PGPLOT_DIR to point to the modified version of PGPLOT
if ($?ESTAR_TKPGPLOT) then
  setenv PGPLOT_DIR $ESTAR_TKPGPLOT
  echo "ESTAR_TKPGPLOT = ${ESTAR_TKPGPLOT}"
else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PGPLOT could not be found, please install PGPLOT 5.2.2" 
  echo "patched for use of the /PTK driver (uses Tk::Pgplot 0.30)" 
  exit
endif
      
# Set up back door for the version number

if ($?ESTAR_VERSION) then
  set pkgvers = $ESTAR_VERSION
  echo "ESTAR_VERSION = ${ESTAR_VERSION}"
else
  set pkgvers = 3.0
endif

# Default for ESTAR_PERL5LIB

if (! $?ESTAR3_PERL5LIB) then
  setenv ESTAR3_PERl5LIB ${ESTAR3_DIR}/lib/perl5
  echo " "
  echo "ESTAR3_PERL5LIB = ${ESTAR3_PERl5LIB}"
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
  echo "Starting Data Mining Process(${ia_args} )"
  ${PERL} ${ESTAR3_DIR}/bin/data_miner.pl ${ia_args}

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.3"
endif
