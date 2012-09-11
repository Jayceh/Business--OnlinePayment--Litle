package Business::OnlinePayment::Litle::ChargebackActivityResponse;
use strict;

sub new{
    my ($class, $args) = @_;
    my $self = bless $args, $class;

    $self->build_subs(
            qw( hash case_id merchant_id order_number invoice_number is_success reason_code reason_code_description ));
    $self->case_id( $args->{'caseId'});
    $self->merchant_id( $args->{'merchantId'});
    $self->order_number( $args->{'litleTxnId'});
    $self->invoice_number( $args->{'orderId'});
    $self->reason_code( $args->{'reasonCode'});
    $self->reason_code_description( $args->{'reasonCodeDescription'});
    $self->hash( $args ); 
    $self->is_success( 1 );

    return $self;
}

sub build_subs {
    my $self = shift;

    foreach(@_) {
        next if($self->can($_));
        eval "sub $_ { my \$self = shift; if(\@_) { \$self->{$_} = shift; } return \$self->{$_}; }"; 
    }
}

1;
