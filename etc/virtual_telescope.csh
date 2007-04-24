
#+ 
#  Name:
#    virtual_telescope.csh

#  Purposes:
#     Sets aliases for eSTAR virtual telescope startup

#  Language:
#    C-shell script

#  Invocation:
#    source $ESTAR_DIR/etc/virtual_telescope.csh

#  Description:
#    Sets all the aliases required to run the eSTAR virtual telescope (an
#    embedded agent that interfaces to a simulated telescope).

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk), Eric Saunders (saunders@astro.ex.ac.uk)

#  History:
#     $Log: virtual_telescope.csh,v $
#     Revision 1.2  2007/04/24 16:52:42  saunders
#     Merged ADP agent branch back into main trunk.
#
#     Revision 1.1.2.1  2006/12/20 09:48:01  saunders
#     Created basic virtual telescope.
#

#  Revision:
#     $Id: virtual_telescope.csh,v 1.2 2007/04/24 16:52:42 saunders Exp $

#  Copyright:
#     Copyright (C) 2003,2006 University of Exeter. All Rights Reserved.

#-

# Need to make sure we use the right PERL (v5.8.6)

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
  echo "Starting Virtual Telescope (${ia_args} )"
  ${PERL} ${ESTAR_DIR}/bin/virtual_telescope.pl ${ia_args}

else
  echo " "
  echo "eSTAR Intelligent Agent Software -- (Version $pkgvers)"
  echo "PERL could not be found, please install Perl v5.8.6"
endif
