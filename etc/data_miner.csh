
#+ 
#  Name:
#    data_miner.csh

#  Purposes:
#     Start the eSTAR Data Mining Process

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR_DIR/etc/wfcam_agent.csh

#  Description:
#    Sets all the aliases required to run the eSTAR Data Miner, passes
#    command line arguements to the perl application.

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  History:
#     $Log: data_miner.csh,v $
#     Revision 1.4  2005/06/29 23:37:40  aa
#     Gzipped & Base64 catalogue transfer, plus addition of a working data mining service
#
#     Revision 1.3  2004/11/30 18:36:27  aa
#     Fixed some of the software decay that had set into the distribution. The user_agent.pl and associated code still needs looking at to ermove direct access to $main::* in some cases
#
#     Revision 1.2  2004/11/12 14:32:04  aa
#     Extensive changes to support jach_agent.pl, see ChangeLog
#
#     Revision 1.1  2004/02/20 00:59:41  aa
#     Added a skeleton data mining process, it has a SOAP server on port 8006
#
#     Revision 1.2  2004/02/19 23:33:54  aa

#  Revision:
#     $Id: data_miner.csh,v 1.4 2005/06/29 23:37:40 aa Exp $

#  Copyright:
#     Copyright (C) 2003 University of Exeter. All Rights Reserved.

#-

# Need to make sure we use the right PERL (v5.8.3)

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
  echo "ESTAR_PERL5LIB = ${ESTAR_PERl5LIB}"
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
  ${PERL} ${ESTAR_DIR}/bin/data_miner.pl ${ia_args}

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
