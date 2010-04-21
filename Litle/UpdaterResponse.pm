package Business::OnlinePayment::Litle::UpdaterResponse;
use strict;

sub new{
    my ($class, $args) = @_;
    my $self = bless $args, $class;

    $self->build_subs(
            qw( cust_id order_number invoice_number batch_date result_code 
            error_message is_success type is_updated new_cardnum new_expdate new_type));
    $self->order_number( $args->{'litleTxnId'});
    $self->invoice_number( $args->{'orderId'});
    $self->batch_date( $args->{'responseTime'});
    $self->result_code( $args->{'response'});
    $self->error_message( $args->{'message'});
    $self->cust_id( $args->{'customerId'});
    $self->is_success( $self->result_code eq '000' ? 1 : 0 );
    $self->type( $args->{'originalCard'} ? 'auth' : 'confirm' );
    if ( $self->type eq 'confirm' 
            && $args->{'updatedCard'}->{'number'} 
            && $args->{'updatedCard'}->{'number'} ne 'N/A'  
    ){
        $self->is_updated(1);
        $self->is_success(1);
    } else {
        $self->is_updated(0);
    }
    if($self->type eq 'confirm') {
       $self->new_cardnum( $args->{'updatedCard'}->{'number'} ); 
       $self->new_type( $args->{'updatedCard'}->{'type'} ); 
       $self->new_expdate( $args->{'updatedCard'}->{'expDate'} ); 
    }

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
