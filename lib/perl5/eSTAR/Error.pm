# eSTAR::Error -----------------------------------------------------------

package eSTAR::Error;

=head1 NAME

eSTAR::Error - Exception handling in an object orientated manner.

=head1 SYNOPSIS

    use eSTAR::Error qw /:try/;
    use eSTAR::Constants qw /:status/;

    # throw an error to be caught
    throw eSTAR::Error::UserAbort( $message, ESTAR__ABORT );
    throw eSTAR::Error::FatalError( $message, ESTAR__FATAL );

    # record and then retrieve an error
    do_stuff();
    my $Error = eSTAR::Error->prior;
    eSTAR::Error->flush if defined $Error;

    sub do_stuff {
        record eSTAR::Error::FatalError( $message, ESTAR__FATAL);
    }
 
    # try and catch blocks
    try {
       stuff();
    }
    catch eSTAR::Error::UserAbort with 
    {
	# normally we just want to catch and then ignore UserAborts
        my $Error = shift;
	agent_exit_normally();
    }
    catch eSTAR::Error::FatalError with 
    {
        # its a fatal error
        my $Error = shift;
	agent_exit_normally($Error);
    }
    otherwise 
    {
       # this block catches croaks and other dies
       my $Error = shift;
       agent_exit_normally($Error);
       
    }; # Don't forget the trailing semi-colon to close the catch block

=head1 DESCRIPTION

C<eSTAR::Error> is based on a modifed version of Graham Barr's C<Error>
package, and more documentation about the (many) features present in
the module but currently unused by the project can be found in the
documentation for that module.

As with the C<Error> package, C<eSTAR::Error> provides two interfaces.
Firstly it provides a procedural interface to exception handling, and
secondly C<eSTAR::Error> is a base class for exceptions that can either
be thrown, for subsequent catch, or can simply be recorded.

If you wish to throw an C<FatalError> or C<UserAbort> then you should
also C<use eSTAR::Constants qw / :status /> so that the eSTAR constants
are available.

=head1 PROCEDURAL INTERFACE

C<eSTAR::Error> exports subroutines to perform exception
handling. These will be exported if the C<:try> tag is used in the
C<use> line.

=over 4

=item try BLOCK CLAUSES

C<try> is the main subroutine called by the user. All other
subroutines exported are clauses to the try subroutine.

The BLOCK will be evaluated and, if no error is throw, try will return
the result of the block.

C<CLAUSES> are the subroutines below, which describe what to do in the
event of an error being thrown within BLOCK.

=item catch CLASS with BLOCK

This clauses will cause all errors that satisfy
C<$err-E<gt>isa(CLASS)> to be caught and handled by evaluating
C<BLOCK>.

C<BLOCK> will be passed two arguments. The first will be the error
being thrown. The second is a reference to a scalar variable. If this
variable is set by the catch block then, on return from the catch
block, try will continue processing as if the catch block was never
found.

To propagate the error the catch block may call C<$err-E<gt>throw>

If the scalar reference by the second argument is not set, and the
error is not thrown. Then the current try block will return with the
result from the catch block.

=item otherwise BLOCK

Catch I<any> error by executing the code in C<BLOCK>

When evaluated C<BLOCK> will be passed one argument, which will be the
error being processed.

Only one otherwise block may be specified per try block

=back

=head1 CLASS INTERFACE

=head2 CONSTRUCTORS

The C<eSTAR::Error> object is implemented as a HASH. This HASH is
initialized with the arguments that are passed to it's
constructor. The elements that are used by, or are retrievable by the
C<eSTAR::Error> class are listed below, other classes may add to these.

	-file
	-line
	-text
	-value

If C<-file> or C<-line> are not specified in the constructor arguments
then these will be initialized with the file name and line number
where the constructor was called from.

The C<eSTAR::Error> package remembers the last error created, and also
the last error associated with a package.

=over 4

=item throw ( [ ARGS ] )

Create a new C<eSTAR::Error> object and throw an error, which will be
caught by a surrounding C<try> block, if there is one. Otherwise it
will cause the program to exit.

C<throw> may also be called on an existing error to re-throw it.

=item with ( [ ARGS ] )

Create a new C<eSTAR::Error> object and returns it. This is defined for
syntactic sugar, eg

    die with eSTAR::Error::FatalError ( $message, UA__FATAL );

=item record ( [ ARGS ] )

Create a new C<eSTAR::Error> object and returns it. This is defined for
syntactic sugar, eg

    record eSTAR::Error::UserAbort ( $message, UA__ABORT )
	and return;

=back

=head2 METHODS

=over 4

=item prior ( [ PACKAGE ] )

Return the last error created, or the last error associated with
C<PACKAGE>

    my $Error = eSTAR::Error->prior;

=item flush ( [ PACKAGE ] )

Flush the last error created, or the last error associated with
C<PACKAGE>.It is necessary to clear the error stack before exiting the
package or uncaught errors generated using C<record> will be reported.

    $Error->flush;

=back

=head2 OVERLOAD METHODS

=over 4

=item stringify

A method that converts the object into a string. By default it returns
the C<-text> argument that was passed to the constructor, appending
the line and file where the exception was generated.

=item value

A method that will return a value that can be associated with the
error. By default this method returns the C<-value> argument that was
passed to the constructor.

=back

=head1 PRE-DEFINED ERROR CLASSES

=over 4

=item eSTAR::Error::FatalError

Used for fatal errors where we want the pipeline to die with cause.
This class can be used to hold simple error strings and values. It's
constructor takes two arguments. The first is a text value, the second
is a numeric value, C<UA__FATAL>. These values are what will be
returned by the overload methods.

=item eSTAR::Error::UserAbort

Used for user generated pipeline aborts, which are handled slightly
differently than fatal errors generated by the pipeline itself. The
constructor for a C<UserAbort> is similar to that for a C<FatalError>
except that the numeric value C<UA__ABORT> is passed.

=back

=head1 KNOWN PROBLEMS

C<eSTAR::Error> which are thrown and not caught inside a C<try> 
block will in turn be caught by C<Tk::Error> if used inside a Tk
environment, as will C<croak> and C<die>. However if is a C<croak> or
C<die> is generated inside a try block and no C<otherwise> block
exists to catch the exception it will be silently ignored until the
application exits, when it will be reported.

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 ACKNOWLEDGMENTS

This class is a slightly modified, with the addition of the C<flush>
method, version of Graham Barr's (gbarr@pobox.com) C<Error>
class. That code was in turn based on code written by Peter Seibel
(peter@weblogic.com) and Jesse Glick (jglick@sig.bsh.com). 

The C<eSTAR::Error> class is a blatent copy of C<ORAC::Error> which 
I wrote during my time at the Joint Astronomy Centre working on the 
ORAC-DR project with Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt> and
Frossie Economou E<lt>frossie@jach.hawaii.eduE<gt>.

=cut

use Error qw/ :try /;
use warnings;
use strict;

use vars qw/$VERSION/;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# flush method added to the base class
use base qw/ Error::Simple /;


# eSTAR::Error::UserAbort -----------------------------------------------

package eSTAR::Error::UserAbort;

use base qw/ eSTAR::Error /;

# eSTAR::Error::FatalError ----------------------------------------------

package eSTAR::Error::FatalError;

use base qw/ eSTAR::Error /;

# eSTAR::Error::Error ---------------------------------------------------

package eSTAR::Error::Error;

use base qw/ eSTAR::Error /;

# ---------------------------------------------------------------------------

1;

