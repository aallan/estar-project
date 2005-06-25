package eSTAR::Constants;

=head1 NAME

eSTAR::Constants - Constants available to the eSTAR system

=head1 SYNOPSIS

  use eSTAR::Constants;
  use eSTAR::Constants qw/ESTAR__OK/;
  use eSTAR::Constants qw/:status/;

=head1 DESCRIPTION

Provide access to constants, necessary to use this module if you wish
to return an ESTAR__ABORT or ESTAR__FATAL status using eSTAR::Error. 

This class has been blatently copied (with minor changes) from the 
ORAC::Constants class written by Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
and Frossie Economou E<lt>frossie@jach.hawaii.eduE<gt> for the ORAC-DR project.

=cut

use strict;
use warnings;

use vars qw/ $VERSION @ISA %EXPORT_TAGS @EXPORT_OK/;
'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

require Exporter;

@ISA = qw/Exporter/;

@EXPORT_OK = qw/ESTAR__OK ESTAR__ERROR ESTAR__ABORT ESTAR__FAULT
                ESTAR__FATAL ESTAR__DEBUG ESTAR__QUIET/;

%EXPORT_TAGS = (
		'status'=>[qw/ ESTAR__OK ESTAR__ERROR ESTAR__ABORT 
                               ESTAR__FATAL ESTAR__DEBUG ESTAR__QUIET
			       ESTAR__FAULT/],
                'bool'=>[qw/ ESTAR__TRUE ESTAR__FALSE/],
                'all'=>[qw/ ESTAR__OK ESTAR__ERROR ESTAR__ABORT 
                            ESTAR__FATAL ESTAR__DEBUG ESTAR__QUIET
                            ESTAR__TRUE ESTAR__FALSE ESTAR__FAULT/]
	       );

Exporter::export_tags('status', 'bool', 'all');

=head1 CONSTANTS

The following constants are available from this module:

=over 4

=item B<ESTAR__DEBUG>

This constant implies that the agent should be verbose.

=cut

use constant ESTAR__DEBUG => 3;

=item B<ESTAR__QUIET>

This constant imples the agent should print no debugging information
to the screen. All such information will still appear in the log files.

=cut

use constant ESTAR__QUIET => 4;

=item B<ESTAR__TRUE>

This constant contains the definition of something being TRUE

=cut

use constant ESTAR__TRUE => 2;

=item B<ESTAR__FALSE>

This constant contains the definition of something being FALSE

=cut

use constant ESTAR__FALSE => 1;

=item B<ESTAR__OK>

This constant contains the definition of good status.

=cut

use constant ESTAR__OK => 0;


=item B<ESTAR__ERROR>

This constant contains the definition of bad status.

=cut

use constant ESTAR__ERROR => -1;

=item B<ESTAR__ABORT>

This constant contains the definition a user aborted process

=cut

use constant ESTAR__ABORT => -2;

=item B<ESTAR__FATAL>

This constant contains the definition a process which has died fatally

=cut

use constant ESTAR__FATAL => -3;


=item B<ESTAR__FAULT>

This constant contains the definition a process which has soem non-fatal fault

=cut

use constant ESTAR__FAULT => -4;


=back

=head1 TAGS

Individual sets of constants can be imported by 
including the module with tags. For example:

  use eSTAR::Constants qw/:status/;

will import all constants associated with status checking.

The available tags are:

=over 4

=item :status

Constants associated with status checking: ESTAR__OK and ESTAR__ERROR.

=back

=item :bool

Constants associated with true, false values

=back

=item :all

All constants.

=head1 USAGE

The constants can be used as if they are subroutines.
For example, if I want to print the value of ESTAR__ERROR I can

  use eSTAR::Constants;
  print ESTAR__ERROR;

or

  use eSTAR::Constants ();
  print eSTAR::Constants::ESTAR__ERROR;

=head1 SEE ALSO

L<constants>

=head1 REVISION

$Id: Constants.pm,v 1.2 2005/06/25 02:25:01 aa Exp $

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Frossie Economou E<lt>frossie@jach.hawaii.eduE<gt>
Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 REQUIREMENTS

The C<constants> package must be available. This is a standard
perl package.

=head1 COPYRIGHT

Copyright (C) 1998-2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut



1;
