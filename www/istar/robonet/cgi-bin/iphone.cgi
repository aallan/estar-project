#!/usr/bin/perl

use Time::localtime;

# G R A B   K E Y W O R D S ---------------------------------------------------

my $string = $ENV{QUERY_STRING};
my @pairs = split( /&/, $string );

# loop through the query string passed to the script and seperate key
# value pairs, remembering to un-Webify the munged data
my %query;
foreach my $i ( 0 ... $#pairs ) {
   my ( $name, $value ) = split( /=/, $pairs[$i] );

   # Un-Webify plus signs and %-encoding
   $value =~ tr/+/ /;
   $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
   $value =~ s/<!--(.|\n)*-->//g;
   $value =~ s/<([^>]|\n)*>//g;

   $query{$name} = $value;
}

# B U I L D   F O R M ----------------------------------------------------------

my $user = $ENV{REMOTE_USER};

print "Content-type: text/html\n\n";

print '<form title="Observation" class="panel" action="robonet/cgi-bin/dumper.cgi" method="PUT">';

print '<h2>Event Information</h2>';

print '<fieldset>';
print '<div class="row">';
print '<label>Target:</label>';
print '<p><input type="text" name="object_name" value="'.$query{target}.'"></p>';
print '</div>';

print '<div class="row">';
print '<label>R.A.:</label>';
print '<input name="ra" value="'.$query{ra}.'">';
print '</div>';

print '<div class="row">';
print '<label>Dec.:</label>';
print '<input name="ra" value="'.$query{dec}.'">';
print '</div>';

print '<input type="hidden" name="equinox" value="J2000">';
print '<input type="hidden" name="concept" value="EXO">';
print '<input type="hidden" name="probability" value="90">';
print '<input type="hidden" name="description" value="Submitted from my iPhone">';

print '</fieldset>';

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
} elsif ( $user eq 'colin' ) {
   $contact_name = 'Colin Snodgrass';
   $contact_email = 'csnodgra@eso.org';
   $contact_phone = '';
}

print '<h2>Contact Information</h2>';

print '<fieldset>';
print '<div class="row">';
print '<label>Contact:</label>';
print '<input type="text" name="name" value="'.$contact_name.'">';
print '</div>';

print '<div class="row">';
print '<label>Email:</label>';
print '<input type="text" name="email" value="'.$contact_email.'">';
print '</div>';

print '</fieldset>';
 
if(  $user eq 'aa' ) {
   print '<input type="hidden" name="project" value="eSTAR">';
} elsif ( $user eq 'rrw' ) {
   print '<input type="hidden" name="project" value="RAPTOR">';
} elsif ( $user eq 'ias' || $user eq 'nrc' || $user eq 'cjm' || $user eq 'mfb' || $user eq 'mjb' || $user eq 'nr' ) {
   print '<input type="hidden" name="project" value="Robonet-1.0">';
} elsif ( $user eq 'md' ) {
   print '<input type="hidden" name="project" value="PLANET">';
} elsif ( $user eq 'ess' || $user eq 'rs' || $user eq 'eh' || $user eq 'yt' )  {
   print '<input type="hidden" name="project" value="LCO>';
} elsif ( $user eq 'colin' ) {
   print '<input type="hidden" name="project" value="ESO">';
}

print '<h2>Observing Constraints</h2>';

print '<fieldset>';
print '<div class="row">';
print '<label>Override?</label>';
print '<div class="toggle" toggled="false" onclick="'."if(document.getElementById( 'setTOOP' ).value==1){document.getElementById( 'setTOOP' ).value=0;}else{document.getElementById( 'setTOOP' ).value=1;};".'">';
print '<span class="thumb"></span>';
print '<span class="toggleOn">ON</span>';
print '<span class="toggleOff">OFF</span>';
print '</div>';
print '</div>';
print '<input type="hidden" id="setTOOP" name="set_toop" value="0">';

print '</fieldset>';

print '<fieldset>';
print '<div class="row">';
print '<label>Exposure:</label>';
print '<p><input type="text" name="exposure" value="'.$query{exposure}.'"> sec</p>';
print '</div>';

print '<div class="row">';
print '<label>Count:</label>';
print '<input type="text" name="group_count" value="'.$query{group}.'">';
print '</div>';

print '<div class="row">';
print '<label>Filter:</label>';
print '<select NAME="filter">';
print ' <option VALUE="R">R';
print ' <option VALUE="I">I';
print ' <option VALUE="V">V';
print ' <option VALUE="B">B';
print '</select>';
print '</div>';
print '</fieldset>';


my ($start_time, $end_time) = start_and_end_timestamp();

print '<fieldset>';
print '<div class="row">';
print '<label>Start:</label>';
print '<input type="text" name="start_time" value="'.$start_time.'">';
print '</div>';

print '<div class="row">';
print '<label>End:</label>';
print '<input type="text" name="end_time" value="'.$end_time.'">';
print '</div>';
print '</fieldset>';

print '<input TYPE="submit" VALUE="Submit Observation">'."\n";

print '</form>';
exit;


print '         <td>'."\n";
print '             <b>Type :</b>   '."\n";
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
