package SQL::Translator::Producer::SQLServer;

use strict;
use warnings;
our ( $DEBUG, $WARN );
our $VERSION = '1.59';
$DEBUG = 1 unless defined $DEBUG;

use SQL::Translator::Schema::Constants;
use SQL::Translator::Utils qw(debug header_comment);
use SQL::Translator::Generator::DDL::SQLServer;

sub produce {
  my $translator = shift;
  SQL::Translator::Generator::DDL::SQLServer->new(
    add_comments    => !$translator->no_comments,
    add_drop_table => $translator->add_drop_table,
  )->schema($translator->schema)
}

sub add_field {
  my ($field) = @_;

  my $generator = SQL::Translator::Generator::DDL::SQLServer->new();

  return sprintf("ALTER TABLE %s ADD %s",
      $generator->quote($field->table->name), $generator->field($field))
}

sub rename_table {
    my ( $old_table, $new_table, $options ) = @_;

    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();

    return
      sprintf( "EXEC sp_rename '%s', '%s', OBJECT", $old_table, $new_table );
}

sub drop_field {
    my ( $field, $options ) = @_;

    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();

    return sprintf(
        "ALTER TABLE %s DROP COLUMN %s",
        $generator->quote( $field->table->name ),
        $generator->quote( $field->name ) );
}

sub alter_drop_constraint {
    my ( $c, $options ) = @_;

    die "constraint has no name" unless $c->name;

    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();

    return sprintf( 'ALTER TABLE %s DROP CONSTRAINT %s',
        map { $generator->quote($_) } $c->table->name, $c->name, );
}

sub alter_field {
    my ( $from_field, $to_field, $options ) = @_;

    die "Can't alter field in another table"
      if ( $from_field->table->name ne $to_field->table->name );

    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();

    return sprintf(
        "ALTER TABLE %s ALTER COLUMN %s",
        $generator->quote( $to_field->table->name ),
        $generator->field($to_field) );
}

sub alter_create_index {
    my ($index, $options) = @_;
    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();
    die "UNIQUE indexes not currently supported" if $index->type ne 'NORMAL';
    return $generator->index($index);
}

sub alter_create_constraint {
    my ( $constraint, $options ) = @_;
    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();
    if ( $constraint->type eq 'FOREIGN KEY' ) {
        return $generator->foreign_key_constraint($constraint);
    }
    else {
        die $constraint->type . 'constraints not currently supported';
    }
}

sub rename_field {
    my ( $from_field, $to_field, $options ) = @_;
    my $generator = SQL::Translator::Generator::DDL::SQLServer->new();
    return
        'EXEC sp_rename ' . "'"
      . $from_field->table->name . '.'
      . $from_field->name . "'" . ', ' . "'"
      . $to_field->name . "'"
      . ", 'COLUMN'";
}

1;

=head1 NAME

SQL::Translator::Producer::SQLServer - MS SQLServer producer for SQL::Translator

=head1 SYNOPSIS

  use SQL::Translator;

  my $t = SQL::Translator->new( parser => '...', producer => 'SQLServer' );
  $t->translate;

=head1 DESCRIPTION

This is currently a thin wrapper around the nextgen
L<SQL::Translator::Generator::DDL::SQLServer> DDL maker.

=head1 Extra Attributes

=over 4

=item field.list

List of values for an enum field.

=back

=head1 TODO

 * !! Write some tests !!
 * Reserved words list needs updating to SQLServer.
 * Triggers, Procedures and Views DO NOT WORK


    # Text of view is already a 'create view' statement so no need to
    # be fancy
    foreach ( $schema->get_views ) {
        my $name = $_->name();
        $output .= "\n\n";
        $output .= "--\n-- View: $name\n--\n\n" unless $no_comments;
        my $text = $_->sql();
        $text =~ s/\r//g;
        $output .= "$text\nGO\n";
    }

    # Text of procedure already has the 'create procedure' stuff
    # so there is no need to do anything fancy. However, we should
    # think about doing fancy stuff with granting permissions and
    # so on.
    foreach ( $schema->get_procedures ) {
        my $name = $_->name();
        $output .= "\n\n";
        $output .= "--\n-- Procedure: $name\n--\n\n" unless $no_comments;
        my $text = $_->sql();
      $text =~ s/\r//g;
        $output .= "$text\nGO\n";
    }

=head1 SEE ALSO

L<SQL::Translator>

=head1 AUTHORS

See the included AUTHORS file:
L<http://search.cpan.org/dist/SQL-Translator/AUTHORS>

=head1 COPYRIGHT

Copyright (c) 2012 the SQL::Translator L</AUTHORS> as listed above.

=head1 LICENSE

This code is free software and may be distributed under the same terms as Perl
itself.

=cut
