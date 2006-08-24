#!/software/perl-5.8.6/bin/perl

use Time::localtime;
use Data::Dumper;
use Config::Simple;

# G R A B   U S E R  I N F O R M A T I O N ------------------------------------

my $user = $ENV{REMOTE_USER};
my $db;
eval { $db = new Config::Simple( "../db/user.dat" ); };
if ( $@ ) {
   error( "$@" );
   exit;
}
  
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

# G R A B   F I L E S ---------------------------------------------------------

my $header;
unless ( open ( FILE, "<../header.inc") ) {
   print "Content-type: text/html\n\n";       
   error( 'Can not open header.inc file' );
   exit;	
}
{
   undef $/;
   $header = <FILE>;
   close FILE;
}
$header =~ s/PAGE_TITLE_STRING/VOEvent Manual Injection/g;
$header =~ s/CALLING_JAVASCRIPT/onload="setFocus()"/;

my $footer;
unless ( open ( FILE, "<../footer.inc") ) {
   print "Content-type: text/html\n\n";       
   error( 'Can not open footer.inc file' );
   exit;	
}
{
   undef $/;
   $footer = <FILE>;
   close FILE;
}
$footer =~ s/LAST_MODIFIED_DATE/ctime()/e;
$footer =~ s/ABOUT_THIS_PAGE//;

# G E N E R A T E   P A G E ------===--------------------------------------


print "Content-type: text/html\n\n";
print $header;
print "<em>From eSTAR (or via <a href='http://www.thinkingtelescopes.lanl.gov/voevent/cgi-bin/index.cgi'>TALONS</a>)</em><br><br>";
#print Dumper( %query);

print '<form action="http://vo.astro.ex.ac.uk/voevent/cgi-bin/submit.cgi" method="PUT">'."\n";
print '<center>'."\n";
print '<table width="95%" cellpadding="2" cellspacing="2" border="0">'."\n";

print '  <!-- ############################################################# -->'."\n";
print '  <!-- # Event Information                                         # -->'."\n";
print '  <!-- ############################################################# -->'."\n";
print '  <tr align="left" valign="middle">'."\n";
print '    <td colspan="3">'."\n";
print '       <u><strong>Message Role</strong></u>'."\n";        
print '    </td>'."\n";
print '  </tr>'."\n";
print '  <tr align="left" valign="top">'."\n";
print '    <td>'."\n";
print '       <b>Role:</b> <select NAME="role">'."\n";
print '  	       <option VALUE="observation"';
print ' selected' if $query{role} eq 'observation';
print '>	Observation'."\n";
print '  	       <option VALUE="prediction"';
print ' selected' if $query{role} eq 'prediction';
print '>	Prediction'."\n";
print ' 	       <option VALUE="utility"';
print ' selected' if $query{role} eq 'utility';
print '>		Utility'."\n";
print '  	       <option VALUE="test"';
print ' selected' if $query{role} eq 'test';
print '>		Test'."\n";
print '	        </select>   '."\n";
print '            <br><i><small>The role of the event message</small></i>'."\n";
print '    </td>'."\n";
print '    <td colspan="2">'."\n";


my $ivorn = "ivo://uk.org.estar/" . $db->param( "$user.author_ivorn") . "#";

print '	           <b>Current IVORN:</b> <code>'. $ivorn .'<i>unique_identifier</i></code>'."\n";
print '           <br><i><small>The root portion of the IVORN</small></i>'."\n";
print '     </td>'."\n";
print '   </tr>'."\n";

print '      <!-- ################################################################ -->'."\n";
print '      <!-- # Description                                                  # -->'."\n";
print '      <!-- ################################################################ -->'."\n";
print '    '."\n";
print '      <tr align="left" valign="top">'."\n";
print '    '."\n";
print '         <td colspan="3">'."\n";
print '	    <TEXTAREA NAME="description", ID="description" ROWS="3", COLS="85">'.$query{description}.'</TEXTAREA>'."\n";
print '           <br><i><small>Human readable description, or other notes.</small></i>'."\n";
print '             <span id="descriptionFailed" class="hidden">'."\n";
print '              Description contains invalid characters'."\n";
print '             </span>'."\n";
print '    '."\n";
print '         </td>'."\n";
print '    '."\n";
print '     </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Citations                                                 # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
print '     <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";
print '           <u><strong>Citations</strong></u>        '."\n";
print '        </td>'."\n";
print '        '."\n";
print '     </tr>'."\n";
print '      <tr align="left" valign="top" colspan="3">'."\n";
print '          <td>'."\n";

my $hidden;
if( $query{hidden_toggle} ne "" ) {
   $hidden = $query{hidden_toggle};
} else {
   $hidden = "disabled";
}
print '             <input type="hidden" id="hidden_toggle" name="hidden_toggle" value="'.$hidden.'">'."\n";
print '             <STYLE type="text/css"> SELECT.d { color: #666; border:2px outset #eee; } </STYLE>'."\n";
print '            <b>Type:</b> <select NAME="cite_type" id="cite_type" class="disabled" disabled>'."\n";
print '  	       <option VALUE=""';
print ' selected' if $query{cite_type} eq '';
print '>		'."\n";
print '  	       <option VALUE="supersedes"';
print ' selected' if $query{cite_type} eq 'supersedes';
print '>	Supersedes'."\n";
print '  	       <option VALUE="followup"';
print ' selected' if $query{cite_type} eq 'followup';
print '>	Follow-up'."\n";
print '  	       <option VALUE="retract"';
print ' selected' if $query{cite_type} eq 'retract';
print '>		Retract'."\n";
print '	    </select>  '."\n";
print '	     <br>'."\n";
print '             <i><small>Type of citation</small></i>'."\n";
print ''."\n";
print '          </td>'."\n";
print '      <td colspan="2">'."\n";
print '             <b>Previous IVORN:</b> <input size="45" id="previous_ivorn" name="previous_ivorn" onblur="validate(this.value, this.id)" value="'.$query{previous_ivorn}.'">'."\n";
print '	     <br>'."\n";
print '             <i><small>IVORN of the message we are citing</small></i>'."\n";
print '             <span id="previous_ivornFailed" class="hidden">'."\n";
print '              This is not a valid IVORN'."\n";
print '              </span>'."\n";

print '          </td>'."\n";
print '     '."\n";
print '     </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Who                                                       # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
print '     <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";
print '           <u><strong>Who</strong></u>        '."\n";
print '        </td>'."\n";
print '        '."\n";

my ( $contact_name, $contact_email, $contact_phone, $short_name, $title );
if ( defined $query{contact_name} && defined $query{contact_email} && 
     defined $query{contact_phone} && defined $query{short_name} && 
     defined $query{title} ) {
   $contact_name = $query{contact_name};
   $contact_email = $query{contact_email};
   $contact_phone = $query{contact_phone};
   $short_name  = $query{short_name};
   $title = $query{title};     
     
} else {
   $contact_name = $db->param( "$user.contact_name" );
   $contact_email = $db->param( "$user.contact_email" );
   $contact_phone = $db->param( "$user.contact_phone" );
   $short_name  = $db->param( "$user.project" );
   $title = $db->param( "$user.institution" );
}   

print '     <tr align="left" valign="top">'."\n";
print '      <td>'."\n";
print '       <b>Name:</b> <input SIZE="20" ID="contact_name" NAME="contact_name" onblur="validate(this.value, this.id)" VALUE="'.$contact_name.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Name of the contact person</small></i>'."\n";
print '             <span id="contact_nameFailed" class="hidden">'."\n";
print '              Invalid contact name?'."\n";
print '              </span>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '       <b>Email:</b> <input SIZE="20" ID="contact_email" NAME="contact_email" onblur="validate(this.value, this.id)" VALUE="'.$contact_email.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Email address for the contact person</small></i>'."\n";
print '             <span id="contact_emailFailed" class="hidden">'."\n";
print '              This is not a valid email address'."\n";
print '              </span>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <b>Phone:</b> <input SIZE="20" ID="contact_phone" NAME="contact_phone" onblur="validate(this.value, this.id)" VALUE="'.$contact_phone.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Phone number for the contact person</small></i>'."\n";
print '             <span id="contact_phoneFailed" class="hidden">'."\n";
print '              This is not a valid UK or US phone number'."\n";
print '              </span>'."\n";
print '       </td>'."\n";
print '    </tr>'."\n";

print '     <tr align="left" valign="top">'."\n";
print '      <td>'."\n";
print '       <b>Project:</b> <input SIZE="20" ID="short_name" NAME="short_name" onblur="validate(this.value, this.id)" VALUE="'.$short_name.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Project affiliation</small></i>'."\n";
print '             <span id="short_nameFailed" class="hidden">'."\n";
print '              Valid projects: eSTAR, RAPTOR'."\n";
print '              </span>'."\n";
print '       </td>'."\n";
print '      <td colspan="2">'."\n";
print '       <b>Institution:</b> <input SIZE="40" ID="title" NAME="title" VALUE="'.$title.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Institutional affiliation</small></i>'."\n";
print '       </td>'."\n";
print '    </tr>'."\n";

my ( $facility, $instrument, $how_reference );
if ( defined $query{facility} && defined $query{how_reference} ) {
   $facility = $query{facility};
   if ( defined $query{instrument} ) {
      $instrument = $query{instrument}; 
   } else {
      $instrument = "";
   }   
   $how_reference = $query{how_reference};
   
} else {
   $facility = $db->param( "$user.facility" );
   $how_reference = $db->param( "$user.facility_url" );
   if( defined $db->param( "$user.instrument" ) ) {
      $instrument = $db->param( "$user.instrument" );
   } else {
      $instrument = "";
   }
}   


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # How                                                       # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
print '     <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";
print '           <u><strong>How</strong></u>        '."\n";
print '        </td>'."\n";
print '        '."\n";
print '     <tr align="left" valign="top">'."\n";
print '      <td>'."\n";
print '       <b>Facility:</b> <input SIZE="20" ID="facility" NAME="facility" onblur="validate(this.value, this.id)" VALUE="'.$facility.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Facility, e.g. telescope or satellite</small></i>'."\n";
print '             <span id="facilityFailed" class="hidden">'."\n";
print '              Valid facilities: Robonet-1.0, TALONS'."\n";
print '              </span>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '       <b>Instrument:</b> <input SIZE="20" NAME="instrument" VALUE="'.$instrument.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Name of instrument</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <b>Reference:</b> <input SIZE="20" ID="how_reference" NAME="how_reference" onblur="validate(this.value, this.id)" VALUE="'.$how_reference.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>URL with facility description</small></i>'."\n";
print '             <span id="how_referenceFailed" class="hidden">'."\n";
print '              Not a valid URL'."\n";
print '              </span>'."\n";
print '       </td>'."\n";
print '    </tr>'."\n";

print '      <!-- ############################################################# -->'."\n";
print '      <!-- # WhereWhen                                                 # -->'."\n";
print '      <!-- ############################################################# -->'."\n";         
print '     <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";
print '           <u><strong>Where &amp; When</strong></u>        '."\n";
print '        </td>'."\n";
print '      </tr>'."\n";
print '      <tr align="left" valign="top">'."\n";
print '         '."\n";
print '          <td colspan="2"><table><tr>'."\n";
print '         <td>'."\n";
print '            <b>R.A. :</b> <input size="15" id="ra" onblur="validate(this.value, this.id)" value="'.$query{ra}.'" name="ra"> '."\n";
print '            <br><i><small>Format: hh mm ss.s</small></i>'."\n";
print '             <span id="raFailed" class="hidden">'."\n";
print '              R.A. is not formatted correctly'."\n";
print '              </span>'."\n";
print '         </td>'."\n";
print '            '."\n";
print '         <td>'."\n";
print '            &nbsp;&nbsp;<b>Dec. :</b> <input id="dec" size="15" onblur="validate(this.value, this.id)" value="'.$query{dec}.'" name="dec"> '."\n";
print '            <br>&nbsp;&nbsp;<i><small>Format: &plusmn;dd mm ss.s</small></i>'."\n";
print '             <span id="decFailed" class="hidden">'."\n";
print '              &nbsp;&nbsp;Dec. is not formatted correctly'."\n";
print '              </span>'."\n";
print '         </td>'."\n";

$query{dist_error} = 4 unless defined $query{dist_error};
print '          <td> '."\n";  
print '             &nbsp;&nbsp;<input type="text" name="dist_error" size="2" value="'.$query{dist_error}.'"> arcmin'."\n";
print '             <br>&nbsp;&nbsp;<i><small>Error</small></i>'."\n";
print '          </td>'."\n";
print '         </tr></table></td>'."\n";

my $time;
if ( defined $query{time} ) {
  $time = $query{time};
} else {
  $time = timestamp();
}
print '         <td>'."\n";
print '            <b>Time:</b> <input size="20" id="time" name="time" onblur="validate(this.value, this.id)" value="'. $time .'"> '."\n";
print '            <br><i><small>Format: YYYY-MM-DDThh:mm:ss (in UTC)</small></i>'."\n";
print '             <span id="timeFailed" class="hidden">'."\n";
print '              Time stamp is not formatted correctly'."\n";
print '              </span>'."\n";
print '         </td>'."\n"; 

        
print '      </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # What                                                      # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
print '     <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";
print '           <u><strong>What</strong></u>        '."\n";
print '        </td>'."\n";

# Parameter 1
print '     <tr align="left" valign="top">'."\n";
print '      <td colspan="3"><table><tr><td>'."\n";
print '       <b>Param:</b> <input SIZE="19" NAME="param_1_name" value="'.$query{param_1_name}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Name of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '        <input SIZE="19" NAME="param_1_ucd" value="'.$query{param_1_ucd}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small><a href="http://www.ivoa.net/Documents/latest/UCDlist.html">UCD</a> for parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_1_value" value="'.$query{param_1_value}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Value of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_1_units" value="'.$query{param_1_units}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Units for parameter</small></i>'."\n";
print '       </td></tr></table>'."\n";
print '    </tr>'."\n";


# Parameter 2
print '     <tr align="left" valign="top">'."\n";
print '      <td colspan="3"><table><tr><td>'."\n";
print '       <b>Param:</b> <input SIZE="19" NAME="param_2_name" value="'.$query{param_2_name}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Name of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '        <input SIZE="19" NAME="param_2_ucd" value="'.$query{param_2_ucd}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small><a href="http://www.ivoa.net/Documents/latest/UCDlist.html">UCD</a> for parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_2_value" value="'.$query{param_2_value}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Value of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_2_units" value="'.$query{param_2_units}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Units for parameter</small></i>'."\n";
print '       </td></tr></table>'."\n";
print '    </tr>'."\n";


# Parameter 3
print '     <tr align="left" valign="top">'."\n";
print '      <td colspan="3"><table><tr><td>'."\n";
print '       <b>Param:</b> <input SIZE="19" NAME="param_3_name" value="'.$query{param_3_name}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Name of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '        <input SIZE="19" NAME="param_3_ucd" value="'.$query{param_3_ucd}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small><a href="http://www.ivoa.net/Documents/latest/UCDlist.html">UCD</a> for parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_3_value" value="'.$query{param_3_value}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Value of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_3_units" value="'.$query{param_3_units}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Units for parameter</small></i>'."\n";
print '       </td></tr></table>'."\n";
print '    </tr>'."\n";


# Parameter 4
print '     <tr align="left" valign="top">'."\n";
print '      <td colspan="3"><table><tr><td>'."\n";
print '       <b>Param:</b> <input SIZE="19" NAME="param_4_name" value="'.$query{param_4_name}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Name of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '        <input SIZE="19" NAME="param_4_ucd" value="'.$query{param_4_ucd}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small><a href="http://www.ivoa.net/Documents/latest/UCDlist.html">UCD</a> for parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_4_value" value="'.$query{param_4_value}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Value of parameter</small></i>'."\n";
print '       </td>'."\n";
print '      <td>'."\n";
print '           <input SIZE="19" NAME="param_4_units" value="'.$query{param_4_units}.'">'."\n";
print '	            <br>'."\n";
print '             <i><small>Units for parameter</small></i>'."\n";
print '       </td></tr></table>'."\n";
print '    </tr>'."\n";


print '      <!-- ############################################################# -->'."\n";
print '      <!-- # Why                                                       # -->'."\n";
print '      <!-- ############################################################# -->'."\n";
print '     <tr align="left" valign="middle">'."\n";
print '        <td colspan="3">'."\n";
print '           <u><strong>Why</strong></u>        '."\n";
print '        </td>'."\n";


#Inference  probability relation
#   Name
#   Concept
#   Description       
    
print '      <tr align="left" valign="top">'."\n";
print '          '."\n";
print '          <td >'."\n";
print '             <b>Name:</b> <input size="15" name="inference_name" value="'.$query{inference_name}.'">'."\n";
print '	     <br>'."\n";
print '             <i><small>Name associated with event</small></i>'."\n";
print '          </td>'."\n";
print '          '."\n";
print '          <td >'."\n";
print '             <b>Concept</b> <input size="15" name="inference_concept" value="'.$query{inference_concept}.'">'."\n";
print '	     <br>'."\n";
print '             <i><small>Concept associated with event</small></i>'."\n";
print '          </td>'."\n";
print '     '."\n";
print '          <td>'."\n";
print '	  '."\n";
print '          <table><tr>'."\n";
print '           <td>'."\n";
print '            <select NAME="inference_relation">'."\n";
print '  	       <option VALUE=""';
print ' selected' if $query{inference_relation} eq '';
print '>	'."\n";
print '  	       <option VALUE="identified"';
print ' selected' if $query{inference_relation} eq 'identified';
print '>	Identified'."\n";
print '  	       <option VALUE="associated"';
print ' selected' if $query{inference_relation} eq 'associated';
print '>	Associated'."\n";
print '	    </select>  '."\n";
print '	     <br>'."\n";
print '             <i><small>Association</small></i>'."\n";
print '	  </td>'."\n";
print '     '."\n";

my $probability = 90;
$probability = $query{probability} if $query{probability} ne "";
print '          <td> '."\n";  
print '             <input type="text" name="probability" size="3" value="'.$probability.'"> %'."\n";
print '             <br><i><small>Probability</small></i>'."\n";
print '          </td>'."\n";
print '	  </tr></table>'."\n";
print '          </td>'."\n";
print '      </tr>'."\n";

print '      <tr align="left" valign="top">'."\n";
print '    '."\n";
print '         <td colspan="3">'."\n";
print '	    <TEXTAREA NAME="inference_description", ROWS="3", COLS="85">'.$query{inference_description}.'</TEXTAREA>'."\n";
print '           <br><i><small>Human readable description, or other notes.</small></i>'."\n";
print '    '."\n";
print '         </td>'."\n";
print '    '."\n";
print '     </tr>'."\n";

print '    <!-- ################################################################ -->'."\n";
print '     <!-- # BUTTONS                                                      # -->'."\n";
print '     <!-- ################################################################ -->'."\n";
print '    <tr align="right" valign="middle">'."\n";
print '     '."\n";
print '        <td colspan="3">'."\n";
print '           <input TYPE="submit" VALUE="Submit" onmouseover="this.focus()">'."\n";
print '           <input TYPE="reset" VALUE="Reset Input Fields" onmouseover="this.focus()">'."\n";
print '        </td>'."\n";
print '     </tr>'."\n";
print ''."\n";
print '   </table>'."\n";
print '   </center>'."\n";
print '  '."\n";
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

sub error {
  my $error = shift;
  my $query = shift;
  
  print "Content-type: text/html\n\n";       
  print "<HTML><HEAD>Error</HEAD><BODY><FONT COLOR='red'>".
        "Error: $error</FONT><BR><BR>";
  if ( defined $query ) {
     print "<P><PRE>" . Dumper( $query ). "</PRE></P>";
  }
  print "</BODY></HTML>";
}

