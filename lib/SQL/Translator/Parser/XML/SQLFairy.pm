package SQL::Translator::Parser::XML::SQLFairy;

# -------------------------------------------------------------------
# $Id: SQLFairy.pm,v 1.6 2004-07-08 19:06:24 grommit Exp $
# -------------------------------------------------------------------
# Copyright (C) 2003 Mark Addison <mark.addison@itn.co.uk>,
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; version 2.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
# 02111-1307  USA
# -------------------------------------------------------------------

=head1 NAME

SQL::Translator::Parser::XML::SQLFairy - parser for SQL::Translator's XML.

=head1 SYNOPSIS

  use SQL::Translator;
  use SQL::Translator::Parser::XML::SQLFairy;

  my $translator     = SQL::Translator->new(
      from           => 'XML-SQLFairy',
      to             => 'MySQL',
      filename       => 'schema.xml',
      show_warnings  => 1,
      add_drop_table => 1,
  );

  print $obj->translate;

=head1 DESCRIPTION

This parser handles the flavor of XML used natively by the SQLFairy
project (SQL::Translator).  The XML must be in the namespace
"http://sqlfairy.sourceforge.net/sqlfairy.xml."
See L<SQL::Translator::Producer::XML::SQLFairy> for details of this format.

You do not need to specify every attribute of the Schema objects as any missing
from the XML will be set to their default values. e.g. A field could be written
using only;

 <sqlf:field name="email" data_type="varchar" size="255" />

Instead of the full;

 <sqlf:field name="email" data_type="varchar" size="255" is_nullable="1"
   is_auto_increment="0" is_primary_key="0" is_foreign_key="0" order="4">
   <sqlf:comments></sqlf:comments>
 </sqlf:field>

If you do not explicitly set the order of items using order attributes on the
tags then the order the tags appear in the XML will be used.

=head2 default_value

Leave the tag out all together to use the default in Schema::Field.
Use empty tags or 'EMPTY_STRING' for a zero lenth string. 'NULL' for an
explicit null (currently sets default_value to undef in the
Schema::Field obj).

  <sqlf:default_value></sqlf:default_value>             <!-- Empty string -->
  <sqlf:default_value>EMPTY_STRING</sqlf:default_value> <!-- Empty string -->
  <sqlf:default_value/>                                 <!-- Empty string -->
  <sqlf:default_value>NULL</sqlf:default_value>         <!-- NULL -->

=head2 ARGS

Doesn't take any extra parser args at the moment.

=cut

# -------------------------------------------------------------------

use strict;

use vars qw[ $DEBUG $VERSION @EXPORT_OK ];
$VERSION = sprintf "%d.%02d", q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/;
$DEBUG   = 0 unless defined $DEBUG;

use Data::Dumper;
use Exporter;
use base qw(Exporter);
@EXPORT_OK = qw(parse);

use base qw/SQL::Translator::Parser/;  # Doesnt do anything at the mo!
use SQL::Translator::Utils 'debug';
use XML::XPath;
use XML::XPath::XMLParser;

sub parse {
    my ( $translator, $data ) = @_;
    my $schema                = $translator->schema;
    local $DEBUG              = $translator->debug;
    my $xp                    = XML::XPath->new(xml => $data);

    $xp->set_namespace("sqlf", "http://sqlfairy.sourceforge.net/sqlfairy.xml");

    #
    # Work our way through the tables
    #
    my @nodes = $xp->findnodes('/sqlf:schema/sqlf:table');
    for my $tblnode (
        sort {
            "".$xp->findvalue('sqlf:order|@order',$a)
            <=>
            "".$xp->findvalue('sqlf:order|@order',$b)
        } @nodes
    ) {
        debug "Adding table:".$xp->findvalue('sqlf:name',$tblnode);

        my $table = $schema->add_table(
            get_tagfields($xp, $tblnode, "sqlf:" => qw/name order/)
        ) or die $schema->error;

        #
        # Fields
        #
        my @nodes = $xp->findnodes('sqlf:fields/sqlf:field',$tblnode);
        foreach (
            sort {
                ("".$xp->findvalue('sqlf:order',$a) || 0)
                <=>
                ("".$xp->findvalue('sqlf:order',$b) || 0)
            } @nodes
        ) {
            my %fdata = get_tagfields($xp, $_, "sqlf:",
                qw/name data_type size default_value is_nullable 
                is_auto_increment is_primary_key is_foreign_key comments/
            );

            if (
                exists $fdata{'default_value'} and
                defined $fdata{'default_value'}
            ) {
                if ( $fdata{'default_value'} =~ /^\s*NULL\s*$/ ) {
                    $fdata{'default_value'}= undef;
                }
                elsif ( $fdata{'default_value'} =~ /^\s*EMPTY_STRING\s*$/ ) {
                    $fdata{'default_value'} = "";
                }
            }

            my $field = $table->add_field( %fdata ) or die $table->error;

            $table->primary_key( $field->name ) if $fdata{'is_primary_key'};

            #
            # TODO:
            # - We should be able to make the table obj spot this when
            #   we use add_field.
            # - Deal with $field->extra
            #
        }

        #
        # Constraints
        #
        @nodes = $xp->findnodes('sqlf:constraints/sqlf:constraint',$tblnode);
        foreach (@nodes) {
            my %data = get_tagfields($xp, $_, "sqlf:",
                qw/name type table fields reference_fields reference_table
                match_type on_delete_do on_update_do/
            );
            $table->add_constraint( %data ) or die $table->error;
        }

        #
        # Indexes
        #
        @nodes = $xp->findnodes('sqlf:indices/sqlf:index',$tblnode);
        foreach (@nodes) {
            my %data = get_tagfields($xp, $_, "sqlf:",
                qw/name type fields options/);
            $table->add_index( %data ) or die $table->error;
        }

    } # tables loop

    #
    # Views
    #
    @nodes = $xp->findnodes('/sqlf:schema/sqlf:view');
    foreach (@nodes) {
        my %data = get_tagfields($xp, $_, "sqlf:",
            qw/name sql fields order/
        );
        $schema->add_view( %data ) or die $schema->error;
    }

    #
    # Triggers
    #
    @nodes = $xp->findnodes('/sqlf:schema/sqlf:trigger');
    foreach (@nodes) {
        my %data = get_tagfields($xp, $_, "sqlf:",
        qw/name perform_action_when database_event fields on_table action order/
        );
        $schema->add_trigger( %data ) or die $schema->error;
    }

    #
    # Procedures
    #
    @nodes = $xp->findnodes('/sqlf:schema/sqlf:procedure');
    foreach (@nodes) {
        my %data = get_tagfields($xp, $_, "sqlf:",
        qw/name sql parameters owner comments order/
        );
        $schema->add_procedure( %data ) or die $schema->error;
    }

    return 1;
}

# -------------------------------------------------------------------
sub get_tagfields {
#
# get_tagfields XP, NODE, NAMESPACE => qw/TAGNAMES/;
# get_tagfields $node, "sqlf:" => qw/name type fields reference/;
#
# Returns hash of data.
# TODO - Add handling of an explicit NULL value.
#

    my ($xp, $node, @names) = @_;
    my (%data, $ns);
    foreach (@names) {
        if ( m/:$/ ) { $ns = $_; next; }  # Set def namespace
        my $thisns = (s/(^.*?:)// ? $1 : $ns);

        my $is_attrib = m/^sql|comments|action$/ ? 0 : 1;

        my $attrib_path = "\@$thisns$_";
        my $tag_path    = "$thisns$_";
        if ( $xp->exists($attrib_path,$node) ) {
            $data{$_} = "".$xp->findvalue($attrib_path,$node);
            warn "Use of '$_' as an attribute is depricated."
                ." Use a child tag instead."
                ." To convert your file to the new version see the Docs.\n"
                unless $is_attrib;
            debug "Got $_=".( defined $data{ $_ } ? $data{ $_ } : 'UNDEF' );
        }
        elsif ( $xp->exists($tag_path,$node) ) {
            $data{$_} = "".$xp->findvalue($tag_path,$node);
            warn "Use of '$_' as a child tag is depricated."
                ." Use an attribute instead."
                ." To convert your file to the new version see the Docs.\n"
                if $is_attrib;
            debug "Got $_=".( defined $data{ $_ } ? $data{ $_ } : 'UNDEF' );
        }
    }

    return wantarray ? %data : \%data;
}

1;

# -------------------------------------------------------------------

=pod

=head1 BUGS

Ignores the order attribute for Constraints, Views, Indices,
Views, Triggers and Procedures, using the tag order instead. (This is the order
output by the SQLFairy XML producer).

=head1 TODO

=over 4

=item *

Support options and extra attributes.

=item *

Test foreign keys are parsed ok.

=item *

Control over defaulting of non-existant tags.

=back

=head1 AUTHOR

Mark D. Addison E<lt>mark.addison@itn.co.ukE<gt>.

=head1 SEE ALSO

perl(1), SQL::Translator, SQL::Translator::Producer::XML::SQLFairy,
SQL::Translator::Schema.

=cut
