#!/software/perl-5.8.8/bin/perl

use Time::localtime;

my $header;
unless ( open ( FILE, "<../header.inc") ) {
   print "Content-type: text/html\n\n";       
   print "<HTML><HEAD>Error</HEAD><BODY>Error: Can not open header.inc file</BODY></HTML>";
   exit;	
}
{
   undef $/;
   $header = <FILE>;
   close FILE;
}
$header =~ s/PAGE_TITLE_STRING/PLANET Override/g;

my $footer;
unless ( open ( FILE, "<../footer.inc") ) {
   print "Content-type: text/html\n\n";       
   print "<HTML><HEAD>Error</HEAD><BODY>Error: Can not open footer.inc file</BODY></HTML>";
   exit;	
}
{
   undef $/;
   $footer = <FILE>;
   close FILE;
}
$footer =~ s/LAST_MODIFIED_DATE/ctime()/e;

my $user = $ENV{REMOTE_USER};

print "Content-type: text/html\n\n";
print $header;

print '<p><b><font color="red">WARNING:</font></b> Since no more than 10 target of opportunity (TOO) override requests per telescope for immediate observations on the RoboNet-1.0 can be made per year, the use of this facility must be restricted to <b>quite exceptional</b> cases, such as a significicant probability for an ongoing planetary anomaly, for which obtaining data at the given time is absolutely crucial. In general, a peak magnification of less than 200 without a previous sign of an anomaly is not seen as such a case. For less urgent cases please submit requests in normal mode, which will queue additional observations onto the Robonet-1.0 telescopes for later observation. All time used by observations requested through this form will be billed to the exo-planet programme allocation.</p>'."\n";

print '<form action="http://estar5.astro.ex.ac.uk/robonet-1.0/cgi-bin/submit.cgi" method="PUT">'."\n";
print '   <center>'."\n";
print '   <table width="95%" cellpadding="2" cellspacing="2" border="0">'."\n";

print '     <tr align="left" valign="middle">'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Event Information                                         # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
     
print '        <td colspan="3">'."\n";
print '           <u><strong>Event Information</strong></u>        '."\n";
print '        </td>'."\n";
        
print '     </tr>'."\n";

print '      <!-- ############################################################# -->'."\n";
print '      <!-- # RA, Dec and Coordinate System                             # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
          
print '      <tr align="left" valign="top">'."\n";
         
print '         <td>'."\n";
print '            <b>R.A. :</b> <input size="15" name="ra"> '."\n";
print '            <br><i><small>Format: hh mm ss.s</small></i>'."\n";
print '         </td>'."\n";
            
print '         <td>'."\n";
print '            <b>Dec. :</b> <input size="15" name="dec"> '."\n";
print '            <br><i><small>Format: &plusmn;dd mm ss.s</small></i>'."\n";
print '         </td>'."\n";
         
print '         <td valign="middle">'."\n";
print '            <input type="radio" name="equinox" value="J2000" checked> J2000'."\n";
print '            <input type="radio" name="equinox" value="B1950">         B1950'."\n";
print '            <br><i><small>Equinox</small></i>'."\n";
print '         </td> '."\n";
                
print '      </tr>'."\n";

print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Event Name & Concept                                      # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
          
    
print '      <tr align="left" valign="top">'."\n";
          
print '          <td >'."\n";
print '             <b>Name :</b> <input size="15" name="object_name">'."\n";
print '	     <br>'."\n";
print '             <i><small>Object name</small></i>'."\n";
print '          </td>'."\n";
     
print '          <td>'."\n";
print '        	    <select NAME="concept">'."\n";
print '  	       <option VALUE="EXO">	Microlensing Anomaly'."\n";
print '  	       <option VALUE="GRB ">	Gamma Ray Burst'."\n";
print '	    </select>  '."\n";
print '	     <br>'."\n";
print '             <i><small>Class of event</small></i>'."\n";

print '          </td>'."\n";
          
print '          <td>   '."\n";
print '             <input type="text" name="probability" size="3" value="90"> %'."\n";
print '             <br><i><small>Probability in percent.</small></i>'."\n";
print '          </td>'."\n";
print '      </tr>'."\n";
      
print '      <!-- ################################################################ -->'."\n";
print '      <!-- # Description                                                  # -->'."\n";
print '      <!-- ################################################################ -->'."\n";
    
print '      <tr align="left" valign="top">'."\n";

print '         <td colspan="3">'."\n";
print '	    <TEXTAREA NAME="description", ROWS="3", COLS="80"> </TEXTAREA>'."\n";
print '           <br><i><small>Human readable description, or other notes.</small></i>'."\n";
            
print '         </td>'."\n";

print '     </tr>'."\n";
    
print '     <tr align="left" valign="middle">'."\n";
     
print '        <td colspan="3">'."\n";
print '           &nbsp;'."\n";
print '        </td>'."\n";
        
print '     </tr>'."\n";

print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Contact Information                                       # -->'."\n";
print '      <!-- ############################################################# -->'."\n";


my ( $contact_name, $contact_email, $contact_phone );
if ( $user eq 'aa' ) {
   $contact_name = "Alasdair Allan";
   $contact_email = 'aa@astro.ex.ac.uk';
   $contact_phone = "+44-1392-264160";
} elsif ( $user eq 'rrw' ) {
   $contact_name = "Robert R. White";
   $contact_email = 'rwhite@lanl.gov';
   $contact_phone = "+1-505-665-3025";
} elsif ($user eq 'ias' ) {
   $contact_name = "Iain Steele";
   $contact_email = 'ias@astro.livjm.ac.uk';
   $contact_phone = '+44-151-2312912'; 
} elsif ( $user eq 'yt' ) {
   $contact_name = "Yiannis Tsapras";
   $contant_email = 'ytsapras@lcogt.net';
   $contant_phone = '+44-151-231-2903';
} elsif ( $user eq 'mfb' ) {
   $contact_name = "Mike Bode";
   $contact_email = 'mfb@astro.livjm.ac.uk';
   $contact_phone = '+44-151-2312920';
} elsif ( $user eq 'mjb' ) {
   $contact_name = "Martin Burgdorf";   
   $contact_email = 'mjb@astro.livjm.ac.uk';
   $contact_phone = '+44-151-2312903';
} elsif ($user eq 'cjm' ) {
   $contat_name = "Chris Mottram";
   $contact_email = 'cjm@astro.livjm.ac.uk';
   $contact_phone = '+44-151-231-2903';
} elsif ($user eq 'nrc' ) {
   $contat_name = "Neil Clay";
   $contact_email = 'nrc@astro.livjm.ac.uk';
   $contact_phone = '+44-151-231-2903';   
} elsif ( $user eq 'md' ) {
   $contact_name = "Martin Dominik";
   $contact_email = 'md35@st-andrews.ac.uk';
   $contact_phone = '+44-1334-463068';
} elsif ( $user eq 'nr' ) {
   $contact_name = 'Nicholas Rattenbury';
   $contact_email = 'nicholas.rattenbury@manchester.ac.uk';
   $contact_phone = '+44-1477-572653';
} elsif ( $user eq 'ess' ) {
   $contact_name = 'Eric Saunders';
   $contact_email = 'saunders@astro.ex.ac.uk';
   $contact_phone = '+44-1392-264124';
} elsif ( $user eq 'rs' ) {
   $contact_name = 'Rachel Street';
   $contact_email = 'rstreet@lcogt.net';
   $contact_phone = '';
} elsif ( $user eq 'eh' ) {
   $contact_name = 'Eric Hawkins';
   $contact_email = 'eric@lcogt.net';
   $contact_phone = '';
}


print '     <tr align="left" valign="middle">'."\n";     
print '        <td colspan="3">'."\n";
print '           <u><strong>Contact Information</strong></u> '."\n";       
print '        </td>'."\n";
        
print '     </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Name, Email, Project                                      # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
          
print '      <tr align="left" valign="top">'."\n";
print '          <td>'."\n";
print '            <b>Name :</b> <input size="15" name="name" value="'. $contact_name .'">'."\n"; 
print '            <br><i><small>Your name</small></i>'."\n";
print '         </td>'."\n";
            
print '         <td>'."\n";
print '            <b>Email:</b> <input size="15" name="email" value="'. $contact_email .'"> '."\n";
print '            <br><i><small>Your email address</small></i>'."\n";
print '         </td>'."\n";
         
print '         <td valign="middle">'."\n";
print '            <b>Project :</b> <select NAME="project">'."\n";

if(  $user eq 'aa' ) {
   print '             <option VALUE="eSTAR">   eSTAR'."\n";
   print '  	       <option VALUE="PLANET">	PLANET'."\n";
   print '  	       <option VALUE="Robonet-1.0">	RoboNet-1.0'."\n";
} elsif ( $user eq 'rrw' ) {
   print '             <option VALUE="RAPTOR"> TALONS'."\n";
   print '             <option VALUE="eSTAR">   eSTAR'."\n";
   print '             <option VALUE="PLANET">  PLANET'."\n";
   print '             <option VALUE="Robonet-1.0">     RoboNet-1.0'."\n";
} elsif ( $user eq 'ias' || $user eq 'nrc' || $user eq 'cjm' || $user eq 'mfb' || $user eq 'mjb' || $user eq 'nr' ) {
   print '             <option VALUE="Robonet-1.0">     RoboNet-1.0'."\n";
   print '             <option VALUE="eSTAR">   eSTAR'."\n";
   print '             <option VALUE="PLANET">  PLANET'."\n";
} elsif ( $user eq 'md' ) {
   print '             <option VALUE="PLANET">  PLANET'."\n";
   print '             <option VALUE="eSTAR">   eSTAR'."\n";
   print '             <option VALUE="Robonet-1.0">     RoboNet-1.0'."\n";
} elsif ( $user eq 'ess' ) {
   print '             <option VALUE="LCO"> LCO GT'."\n";
   print '             <option VALUE="eSTAR">   eSTAR'."\n";
   print '             <option VALUE="PLANET">  PLANET'."\n";
   print '             <option VALUE="Robonet-1.0">     RoboNet-1.0'."\n";
} elsif ( $user eq 'rs' | $user eq 'eh' || $user eq 'yt' )  {
   print '             <option VALUE="LCO"> LCO GT'."\n";
   print '             <option VALUE="eSTAR">   eSTAR'."\n";
   print '             <option VALUE="PLANET">  PLANET'."\n";
   print '             <option VALUE="Robonet-1.0">     RoboNet-1.0'."\n";
}

print '	    </select>  '."\n";
print '	     <br>'."\n";
print '             <i><small>Your project affiliation</small></i>'."\n";

print '         </td> '."\n";
                
print '      </tr>'."\n";
    
print '     <tr align="left" valign="middle">'."\n";
     
print '        <td colspan="3">'."\n";
print '           &nbsp;'."\n";
print '        </td>'."\n";
        
print '     </tr>'."\n";

print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Observing Information                                     # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
   
print '     <tr align="left" valign="middle">'."\n";
     
print '        <td colspan="3">'."\n";
print '           <u><strong>Observing Constraints</strong></u> '."\n";       
print '        </td>'."\n";
        
print '     </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Type, Group, Count                                        # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
          
print '      <tr align="left" valign="top">'."\n";
      
         
print '         <td>'."\n";
print '             <b>Type :</b> <select NAME="type">'."\n";
print '  	       <option VALUE="toop">	Target of opportunity '."\n";
print '  	       <option VALUE="normal">	Normal observation'."\n";
print '	    </select>  '."\n";
print '	     <br>'."\n";
print '             <i><small>Type of observation requested</small></i>'."\n";
print '         </td>'."\n";
            
print '         <td>'."\n";
print '            <b>Exposure Time:</b> <input size="5" name="exposure"> '."\n";
print '            <br><i><small>Exposure time (secs) (<a target="_blank" href="http://telescope.livjm.ac.uk/Info/TelInst/Inst/calc/">Exposure Time Calculator</a>)</small></i>'."\n";
print '         </td>'."\n";
         
print '         <td valign="middle">'."\n";

print '            <b>Group Count:</b> <input size="5" name="group_count"> '."\n";
print '            <br><i><small>Exposures in the group</small></i>'."\n";
                
print '      </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Series, Interval, Tolerance                               # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
          
print '      <tr align="left" valign="top">'."\n";
      

print '         <td valign="middle">'."\n";

print '            <b>Series Count:</b> <input size="5" name="series_count"> '."\n";
print '            <br><i><small>Exposures in the series</small></i>'."\n";
           
print '         <td>'."\n";
print '            <b>Interval:</b> <input size="5" name="interval"> '."\n";
print '            <br><i><small>Interval between exposure groups (secs)</small></i>'."\n";
print '         </td>'."\n";
            
print '         <td>'."\n";
print '            <b>Tolerance:</b> <input size="5" name="tolerance"> '."\n";
print '            <br><i><small>Tolerance on the intervals (secs)</small></i>'."\n";
print '         </td>'."\n";
         

                
print '      </tr>'."\n";
     

print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Start and End Time                                        # -->'."\n";
print '      <!-- ############################################################# -->'."\n";

my ($start_time, $end_time) = start_and_end_timestamp();
          
print '      <tr align="left" valign="top">'."\n";
#print '      <td colspan="3">'."\n";
#print '         <table border="0" width="100%">'."\n";
#print '         <tr>'."\n";

print '         <td valign="top">'."\n";
print '            <b>Start Time:</b>'."\n";
print '             <input size="23" name="start_time" value="'. $start_time .'">'."\n";
print '            <br><i><small>Format: YYYY-MM-DDThh:mm:ss (in UTC)</small></i>     '."\n";     
print '         </td>'."\n";
            
print '         <td valign="top">'."\n";
print '            <b>End Time:</b>'."\n";
print '             <input size="23" name="end_time" value="'. $end_time .'"> '."\n";
print '            <br><i><small>Format: YYYY-MM-DDThh:mm:ss (in UTC)</small></i>     '."\n";     
print '         </td>'."\n";
              
#print '         </tr>'."\n";
#print '         </table> '."\n";
#print '      </td>'."\n";

print '         <td>'."\n";
print '             <b>Type :</b> <select NAME="filter">'."\n";
print '  	       <option VALUE="R">	R '."\n";
print '  	       <option VALUE="I">	I'."\n";
print '  	       <option VALUE="V">	V'."\n";
print '  	       <option VALUE="B">	B'."\n";
print '	    </select>  '."\n";
print '	     <br>'."\n";
print '             <i><small>Filter requested</small></i>'."\n";
print '         </td>'."\n";

print '      </tr>'."\n";

#print '      <!-- ############################################################# -->'."\n";
#print '      <!-- # Observing Information                                     # -->'."\n";
#print '      <!-- ############################################################# -->'."\n";
   
#print '     <tr align="left" valign="middle">'."\n";
     
#print '        <td colspan="3">'."\n";
#print '           <u><strong>Authorisation</strong></u>  '."\n";      
#print '        </td>'."\n";
        
#print '     </tr>'."\n";
    
#print '     <tr align="left" valign="middle">'."\n";
     
#print '        <td valign="middle">'."\n";
#print '            <b>User :</b> <input size="15" name="user_name"> '."\n";
#print '	     <br>'."\n";
#print '             <i><small>Your <b><font color="red">e</font>STAR</b> user name</small></i>'."\n";

#print '        </td>'."\n";


#print '        <td valign="middle">'."\n";
#print '            <b>Password :</b> <input size="15" type="password" name="user_pass"> '."\n";
#print '	     <br>'."\n";
#print '             <i><small>Your <b><font color="red">e</font>STAR</b> password</small></i>'."\n";
#print '        </td>'."\n";


#print '        <td  valign="middle">'."\n";
#print '           &nbsp;'."\n";
#print '        </td>'."\n";
        
#print '     </tr>'."\n";


print '     <!-- ################################################################ -->'."\n";
print '     <!-- # ALL TELESCOPES                                               # -->'."\n";
print '     <!-- ################################################################ -->'."\n";

print '   <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";

print '          <b>Observe on all telescopes? <input type="checkbox" name="all_telescopes" value="1"> </b>'."\n";
print '        </td>'."\n";
print '     </tr>'."\n";

print '     <!-- ################################################################ -->'."\n";
print '     <!-- # BUTTONS                                                      # -->'."\n";
print '     <!-- ################################################################ -->'."\n";

print '    <tr align="right" valign="middle">'."\n";
     
print '        <td colspan="3">'."\n";
print '           <input TYPE="submit" VALUE="Submit Event">'."\n";
print '           <input TYPE="reset" VALUE="Reset Input Fields">'."\n";
print '        </td>'."\n";
print '     </tr>'."\n";

print '   </table>'."\n";
print '   </center>'."\n";
  
print '</form>'."\n";
print $footer;

exit;

sub timestamp {
   # ISO format 2006-01-05T08:00:00
   		     
   my $year = 1900 + localtime->year();
   
   my $month = localtime->mon() + 1;
   $month = "0$month" if $month < 10;
   
   my $day = localtime->mday();
   $day = "0$day" if $day < 10;
   
   my $hour = localtime->hour();
   $hour = "0$hour" if $hour < 10;
   
   my $min = localtime->min();
   $min = "0$min" if $min < 10;
   
   my $sec = localtime->sec();
   $sec = "0$sec" if $sec < 10;
   
   my $timestamp = $year ."-". $month ."-". $day ."T". 
   		   $hour .":". $min .":". $sec;

   return $timestamp;
}   

sub start_and_end_timestamp {

   my $year = 1900 + localtime->year();
   my $month = localtime->mon() + 1;
   my $day = localtime->mday();

   my $hour = localtime->hour();
   my $min = localtime->min();
   $sec = localtime->sec();

   # could be last day of the month
   if ( $day >= 28 && $day <= 31 ) {
  
     # Special case for Februry
     if ( $month == 2 ) {
  
        # insert code to handle leap year here

        $month = $month + 1;
        $day = 1;
     
     } elsif ( $month == 9 || $month == 4 || $month == 6 || $month == 11 ) {
        if( $day == 30 ) {
          $month = $month + 1;
          $day = 1;
        }
    
     } elsif ( $day == 31 ) {
        $month = $month + 1;
        $day = 1;
     }  
   }

   # fix roll over errors
   my $dayplusone = $day + 1;
   my $hourplustwelve = $hour + 13; # Actually plus 13 hours, not 12 now!
   if( $hourplustwelve > 24 ) {
     $hourplustwelve = $hourplustwelve - 24;
   } 
 
   # fix less than 10 errors
   $month = "0$month" if $month < 10;
   $day = "0$day" if $day < 10;   
   $hour = "0$hour" if $hour < 10;   
   $min = "0$min" if $min < 10;   
   $sec = "0$sec" if $sec < 10;   
   $dayplusone = "0$dayplusone" if $dayplusone < 10;   
   $hourplustwelve = "0$hourplustwelve" if $hourplustwelve < 10;
 
   # defaults of now till 12 hours later  
   # modify start time
   my $start_time = "$year-$month-$day" . "T". $hour.":".$min.":".$sec . "+0000";


   # modify end time
   my $end_time = "$year-$month-$dayplusone" . 
               "T". $hourplustwelve.":".$min.":".$sec . "+0000"; 

 
   return ( $start_time, $end_time );
}
