package Business::OnlinePayment::Litle::ErrorCodes;
use strict;
use warnings;

use Exporter 'import';
use vars qw(@EXPORT_OK $VERSION);

@EXPORT_OK = qw(lookup %ERRORS);
$VERSION = '0.01';

our %ERRORS;

sub lookup {
    my $code = shift;
    return if not $code or not defined $ERRORS{$code};
    return $ERRORS{$code};
}


%ERRORS = (
          '000' => {
                     notes => 'Approved'
                   },
          '010' => {
                     notes => 'Partially Approved'
                   },
          '100' => {
                     notes => 'Processing Network Unavailable',
                     reason  => 'Visa/MC network is down',
                     status => 'Soft',
                   },
          '101' => {
                     notes => 'Issuer Unavailable',
                     reason => 'Issuing bank network is down',
                     status => 'Soft',
                   },
          '102' => {
                     notes => 'Re-submit Transaction'
                   },
          '110' => {
                     notes => 'Insufficient Funds'
                   },
          '111' => {
                     notes => 'Authorization amount has already been depleted'
                   },
          '120' => {
                     notes => 'Call Issuer'
                   },
          '121' => {
                     notes => 'Call AMEX'
                   },
          '122' => {
                     notes => 'Call Diners Club'
                   },
          '123' => {
                     notes => 'Call Discover'
                   },
          '124' => {
                     notes => 'Call JBS'
                   },
          '125' => {
                     notes => 'Call Visa/MasterCard'
                   },
          '126' => {
                     notes => 'Call Issuer - Update Cardholder Data'
                   },
          '127' => {
                     notes => 'Exceeds Approval Amount Limit'
                   },
          '130' => {
                     notes => 'Call Indicated Number'
                   },
          '140' => {
                     notes => 'Update Cardholder Data'
                   },
          '191' => {
                     notes => 'The merchant is not registered in the update program.'
                   },
          '301' => {
                     notes => 'Invalid Account Number'
                   },
          '302' => {
                     notes => 'Account Number Does Not Match Payment Type'
                   },
          '303' => {
                     notes => 'Pick Up Card'
                   },
          '304' => {
                     notes => 'Lost/Stolen Card'
                   },
          '305' => {
                     notes => 'Expired Card'
                   },
          '306' => {
                     notes => 'Authorization has expired; no need to reverse'
                   },
          '307' => {
                     notes => 'Restricted Card'
                   },
          '308' => {
                     notes => 'Restricted Card - Chargeback'
                   },
          '310' => {
                     notes => 'Invalid track data'
                   },
          '311' => {
                     notes => 'Deposit is already referenced by a chargeback'
                   },
          '320' => {
                     notes => 'Invalid Expiration Date'
                   },
          '321' => {
                     notes => 'Invalid Merchant'
                   },
          '322' => {
                     notes => 'Invalid Transaction'
                   },
          '323' => {
                     notes => 'No such issuer'
                   },
          '324' => {
                     notes => 'Invalid Pin'
                   },
          '325' => {
                     notes => 'Transaction not allowed at terminal'
                   },
          '326' => {
                     notes => 'Exceeds number of PIN entries'
                   },
          '327' => {
                     notes => 'Cardholder transaction not permitted'
                   },
          '328' => {
                     notes => 'Cardholder requested that recurring or installment payment be stopped'
                   },
          '330' => {
                     notes => 'Invalid Payment Type'
                   },
          '335' => {
                     notes => 'This method of payment does not support authorization reversals'
                   },
          '340' => {
                     notes => 'Invalid Amount'
                   },
          '346' => {
                     notes => 'Invalid billing descriptor prefix'
                   },
          '347' => {
                     notes => 'Invalid billing descriptor'
                   },
          '349' => {
                     notes => 'Do Not Honor'
                   },
          '350' => {
                     notes => 'Generic Decline'
                   },
          '351' => {
                     notes => 'Decline - Request Positive ID'
                   },
          '352' => {
                     notes => 'Decline CVV2/CID Fail'
                   },
          '353' => {
                     notes => 'Merchant requested decline due to AVS result'
                   },
          '354' => {
                     notes => '3-D Secure transaction not supported by merchant'
                   },
          '355' => {
                     notes => 'Failed velocity check'
                   },
          '356' => {
                     notes => 'Invalid purchase level III, the transaction contained bad or missing data'
                   },
          '360' => {
                     notes => 'No transaction found with specified litleTxnId'
                   },
          '361' => {
                     notes => 'Authorization no longer available'
                   },
          '362' => {
                     notes => 'Transaction Not Voided - Already Settled'
                   },
          '363' => {
                     notes => 'Auto-void on refund'
                   },
          '365' => {
                     notes => 'Total credit amount exceeds capture amount'
                   },
          '370' => {
                     notes => 'Internal System Error - Call Litle'
                   },
          '400' => {
                     notes => 'No Email Notification was sent for the transaction'
                   },
          '401' => {
                     notes => 'Invalid Email Address'
                   },
          '500' => {
                     notes => 'The account number was changed'
                   },
          '501' => {
                     notes => 'The account was closed'
                   },
          '502' => {
                     notes => 'The expiration date was changed'
                   },
          '503' => {
                     notes => 'The issuing bank does not participate in the update program'
                   },
          '504' => {
                     notes => 'Contact the cardholder for updated information'
                   },
          '505' => {
                     notes => 'No match found'
                   },
          '506' => {
                     notes => 'No changes found'
                   },
          '601' => {
                     notes => 'Soft Decline - Primary Funding Source Failed'
                   },
          '602' => {
                     notes => 'Soft Decline - Buyer has alternate funding source'
                   },
          '610' => {
                     notes => 'Hard Decline - Invalid Billing Agreement Id'
                   },
          '611' => {
                     notes => 'Hard Decline - Primary Funding Source Failed'
                   },
          '612' => {
                     notes => 'Hard Decline - Issue with Paypal Account'
                   },
          '701' => {
                     notes => 'Under 18 years old'
                   },
          '702' => {
                     notes => 'Bill to outside USA'
                   },
          '703' => {
                     notes => 'Bill to address is not equal to ship to address'
                   },
          '704' => {
                     notes => 'Declined, foreign currency, must be USD'
                   },
          '705' => {
                     notes => 'On negative file'
                   },
          '706' => {
                     notes => 'Blocked agreement'
                   },
          '707' => {
                     notes => 'Insufficient buying power'
                   },
          '708' => {
                     notes => 'Invalid Data'
                   },
          '709' => {
                     notes => 'Invalid Data - data elements missing'
                   },
          '710' => {
                     notes => 'Invalid Data - data format error'
                   },
          '711' => {
                     notes => 'Invalid Data - Invalid T&C version'
                   },
          '712' => {
                     notes => 'Duplicate transaction'
                   },
          '713' => {
                     notes => 'Verify billing address'
                   },
          '714' => {
                     notes => 'Inactive Account'
                   },
          '716' => {
                     notes => 'Invalid Auth'
                   },
          '717' => {
                     notes => 'Authorization already exists for the order'
                   },
          '900' => {
                     notes => 'Invalid Bank Routing Number'
                   }
        );

=head1 NAME

Business::OnlinePayment::Litle::ErrorCodes - Map given codes with more verbose messages

=head1 SYNOPSIS
    
    use Business::OnlinePayment::Litle::ErrorCodes 'lookup';
    my $result = lookup( $result_code );
    # $result = { reason => ..., notes => ..., status => ... };

or
      
    use Business::OnlinePayment::Litle::ErrorCodes '%ERRORS';
    my $result = $ERRORS{ $result_code };
               
=head1 DESCRIPTION
               
This module provides a method to lookup extended codes to Litle & Co API responses
                
=head2 lookup CODE
      
Takes the result code returned in your Litle response.  Returns a 
hashref containing three keys, C<reason>, C<status>, and C<notes> (which may be empty) if
the lookup is successful, undef otherwise.  This allows for more descriptive error messages, as well as categorization into hard and soft failure types.
      
=head1 AUTHOR

Jason (Jayce^) Hall <jayce@lug-nut.com>

=head1 AKNOWLEDGEMENTS

Thomas Sibley <trs@bestpractical.com> wrote the AIM module.  This follows the same pattern
               
=head1 COPYRIGHT AND LICENSE
                
Copyright (c) 2010.
              
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.
               
=cut  

1;
