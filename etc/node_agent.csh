
#+ 
#  Name:
#    node_agent.csh

#  Purposes:
#     Sets aliases for eSTAR DN Embedded Agent startup

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR_DIR/etc/node_agent.csh

#  Description:
#    Sets all the aliases required to run the eSTAR DN Embedded Agent

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  History:
#     $Log: node_agent.csh,v $
#     Revision 1.1  2005/04/29 09:29:46  aa
#     Added a port of the node_agent.pl and associated modules
#
#     Revision 1.1  2003/06/02 17:59:40  aa
#     Inital DN embedded agent, non-functional, problem with TCP client/server
#
#
#

#  Revision:
#     $Id: node_agent.csh,v 1.1 2005/04/29 09:29:46 aa Exp $

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
  set pkgvers = 2.0
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
  echo "Starting Embedded Agent (${ia_args} )"
  ${PERL} ${ESTAR_DIR}/bin/node_agent.pl ${ia_args}

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
