#!/bin/tcsh 
# for debugging add -xv


# CONFIGURATION
# -------------

# Current Working Directory
set pwd = `pwd`
set homedir = "/home/`whoami`"      

# global tags
set VERSION = "1.0"
set MODIFIED = "19-FEB-2004"

# STARTUP
# -------

# On Interrupt
onintr cleanup

# Colours
set esc = "\033["
set normal = "${esc}39;29m"
set blue = "${esc}39;34m"
set green = "${esc}39;32m"
set red = "${esc}39;31m"
set cyan = "${esc}39;36m"

echo "\n${cyan}Perl Installtion${normal}"
echo -n "Path: "
set pathtoperl = $<

echo "${cyan}SSL Installtion${normal}"
echo -n "Path: "
set ssldir = $<

echo "${cyan}Sybase Installtion${normal}"
echo -n "Path: "
set sybase = $<

echo "${cyan}CFITSIO Installtion${normal}"
echo -n "Path: "
set cfitsio = $<

echo "${cyan}Exeter CVS Checkout${normal}"
echo -n "Path: "
set modules = $<

echo "${cyan}JACH CVS Checkout${normal}"
echo -n "Path: "
set jachmodules = $<

# CONFIGURATION
# -------------

# user agent directory
set working = "${homedir}/third_generation"

# list of modules
set listfile = "${working}/etc/install/list.dat"

# Temporary Directory
set tmp = "/tmp"

# Perl 5.8.3 
set perl5bin = "${pathtoperl}/bin/perl"

# ENVIRONMENT VARIABLES
# ---------------------

setenv LD_LIBRARY_PATH ${dbdir}:${homedir}/lib
setenv SYBASE ${sybase}
setenv LANG C

# INSTALL MODULES
# ---------------

echo "\n${cyan}Installing modules from Perl Modules package${normal}\n"

# check to see we have the list of modules in the right place
if ( ! -e ${listfile} ) then
  echo "${red}Error: Can not find ${listfile}${normal}"
  exit
endif  

set counter = 1
set length = `wc -l ${listfile} | awk '{split($0,a," "); print a[1]}'`
while ( $counter <= $length ) 
   set module = `cat ${listfile} | head -n ${counter} | tail -1`

   # Check for commented out modules
   set hash = `echo ${module} | awk '{split($0,a," "); print a[1]}'`

   if( $hash != "#" ) then 
      
      echo "${cyan}Installing ${module} (${counter} of ${length})${normal}"
      cd ${modules}/${module}
   
      # Check to see if the module is already installed?
      # <-- INSERT CODE HERE -->   

   
      # special cases for "perl Makefile.PL step"
      if ( $module == "CPAN/Crypt-SSLeay-0.49" ) then
         echo $ssldir | ${perl5bin} Makefile.PL  
      else if ( $module == "CPAN/Net-SSLeay-1.22" ) then
         ${perl5bin} Makefile.PL $ssldir     
      else if ( $module == "CPAN/Astro-FITS-CFITSIO-1.01" ) then
         ${perl5bin} Makefile.PL $cfitsio           
      else if ( $module == "CPAN/HTML-Parser-3.28" ) then
         echo "y" | ${perl5bin} Makefile.PL  
      else if ( $module == "CPAN/libwww-perl-5.69" ) then
         echo "y\n y\n y\n y\n y\n y\n y" | ${perl5bin} Makefile.PL 
      else if ( $module == "CPAN/SOAP-Lite-0.55" ) then
         echo "y\n y\n y\n y\n y\n n\n n\n y\n y\n n\n n\n y\n y\n y\n n" \
         | ${perl5bin} Makefile.PL  
      else if ( $module == "CPAN/XML-SAX-0.12" ) then
         echo "y" | ${perl5bin} Makefile.PL  
      else if ( $module == "CPAN/Time-Piece-1.08" ) then
         echo "${cyan}Need to install Time::Seconds manually...${normal}" 
         ${perl5bin} Makefile.PL  
      else if ( $module == "CPAN/DBD-Sybase-1.00" ) then
         echo "${cyan}Assuming Sybase installed in ${sybase}${normal}..."  
         echo "SYB_TMP\nomp\n x70ecLPh" | ${perl5bin} Makefile.PL  
      else if ( $module == "CPAN/XML-LibXML-1.54" ) then
         echo "${cyan}" \
          "Need to insert 'dHTX' in line 82 of perl-libxml-sax.c${normal}" 
         ${perl5bin} Makefile.PL  
      else if ( $module == "JACH/Astro-FITS-Header-2.6.2" ) then
         echo "${cyan}Installing Astro::FITS::Header" \
              "directly from JACH CVS${normal}" 
         cd ${jachmodules}/Astro/FITS/Header
         ${perl5bin} Makefile.PL  
      else
         ${perl5bin} Makefile.PL  
      endif

      make 
      make install  
      make clean  
      echo "${green}Done...${normal}"
   else
      echo "${red}Skipping module ${counter} of ${length}...${normal}"
   endif 
   @ counter = $counter + 1 
     
end

# COMPLETE
# --------
echo "\n${green}Installation complete${normal}"

# CLEAN UP
# --------

cleanup:
echo "\n${green}Cleaning up...${normal}"
cd ${pwd}
echo "${green}Done...${normal}"

