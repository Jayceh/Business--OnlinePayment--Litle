#!/usr/bin/perl -w

use Test::More;
use Storable;

## grab info from the ENV
my $login = $ENV{'BOP_USERNAME'} ? $ENV{'BOP_USERNAME'} : 'TESTMERCHANT';
my $password = $ENV{'BOP_PASSWORD'} ? $ENV{'BOP_PASSWORD'} : 'TESTPASS';
my $merchantid = $ENV{'BOP_MERCHANTID'} ? $ENV{'BOP_MERCHANTID'} : 'TESTMERCHANTID';
my @opts = ('default_Origin' => 'RECURRING' );

## grab test info from the storable
my $data = retrieve('t/data.str');

use Data::Dumper;
print Dumper( keys %{$data} );

#plan tests => 319;
  
use_ok 'Business::OnlinePayment';
ok( $login, 'Supplied a Login' );
ok( $password, 'Supplied a Password' );
like( $merchantid, qr/^\d+/, 'MerchantID');

my %orig_content = (
    type           => 'VISA',
    login          => $login,
    password       => $password,
    merchantid      =>  $merchantid,
    action         => 'Authorization Only', #'Normal Authorization',
    description    => 'FST*BusinessOnlinePayment',
#    card_number    => '4007000000027',
    card_number    => '4457010000000009',
    cvv2           => '123',
    expiration     => expiration_date(),
    amount         => '49.95',
    name           => 'Tofu Beast',
    email          => 'ippay@weasellips.com',
    address        => '123 Anystreet',
    city           => 'Anywhere',
    state          => 'UT',
    zip            => '84058',
    country        => 'US',      # will be forced to USA
    customer_id    => 'tfb',
    company_phone   => '801.123-4567',
    url             =>  'support.foo.com',
    invoice_number  => '1234',
    ip              =>  '127.0.0.1',
    products        =>  [
    {   description =>  'First Product',
        sku         =>  'sku',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  500,
        discount    =>  0,
        code        =>  1,
        cost        =>  500,
    },
    {   description =>  'Second Product',
        sku         =>  'sku',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  1500,
        discount    =>  0,
        code        =>  2,
        cost        =>  500,
    }

    ],
);

my %content = %orig_content;
### Litle AUTH Tests
print '-'x70;
print "AUTH TESTS\n";
my %auth_resp = ();
foreach my $account ( @{$data->{'account'}} ){
    $content{'amount'} = $account->{'Amount'};
    $content{'type'} = $account->{'CardType'};
    $content{'card_number'} = $account->{'AccountNumber'};
    $content{'expiration'} = $account->{'ExpDate'};
    $content{'cvv2'} = $account->{'CardValidation'};
    $content{'cvv2'} = '' if $content{'cvv2'} eq 'blank';
    $content{'invoice_number'} = $account->{'OrderId'};
    ## get the response validation set for this order
    my ($address) = grep { $_->{'OrderId'} ==  $account->{'OrderId'} } @{ $data->{'address'} };
    $content{'name'} = $address->{'Name'};
    $content{'address'} = $address->{'Address1'};
    $content{'address2'} = $address->{'Address2'};
    $content{'city'} = $address->{'City'};
    $content{'state'} = $address->{'State'};
    $content{'state'} = $address->{'State'};
    $content{'zip'} = $address->{'Zip'};

    my ($resp_validation) = grep { $_->{'OrderId'} ==  $account->{'OrderId'} } @{ $data->{'auth_response'} };
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        tx_check(
            $tx,
            desc          => "Auth Only",
            is_success    => $resp_validation->{'Message'} eq 'Approved' ? 1 : 0,
            result_code   => $resp_validation->{'Response Code'},
            error_message => $resp_validation->{'Message'},
            authorization => $resp_validation->{'Auth Code'},
            avs_code      => $resp_validation->{'AVS Result'},
            cvv2_response => $resp_validation->{'Card Validation Result'},
        );

        $auth_resp{ $account->{'OrderId'} } = $tx->order_number if $tx->is_success;
    }
}

print '-'x70;
print "SALE\n";
my %sale_resp = ();
%content = %orig_content;

foreach my $account ( @{$data->{'account'}} ){
    $content{'action'} = 'Normal Authorization';
    $content{'amount'} = $account->{'Amount'};
    $content{'type'} = $account->{'CardType'};
    $content{'card_number'} = $account->{'AccountNumber'};
    $content{'expiration'} = $account->{'ExpDate'};
    $content{'cvv2'} = $account->{'CardValidation'};
    $content{'cvv2'} = '' if $content{'cvv2'} eq 'blank';
    $content{'invoice_number'} = $account->{'OrderId'};
    ## get the response validation set for this order
    my ($address) = grep { $_->{'OrderId'} ==  $account->{'OrderId'} } @{ $data->{'address'} };
    $content{'name'} = $address->{'Name'};
    $content{'address'} = $address->{'Address1'};
    $content{'address2'} = $address->{'Address2'};
    $content{'city'} = $address->{'City'};
    $content{'state'} = $address->{'State'};
    $content{'state'} = $address->{'State'};
    $content{'zip'} = $address->{'Zip'};

    my ($resp_validation) = grep { $_->{'OrderId'} ==  $account->{'OrderId'} } @{ $data->{'sales'} };
    #print Dumper(\%content);
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        tx_check(
            $tx,
            desc          => "Sale Order",
            is_success    => $resp_validation->{'Message'} eq 'Approved' ? 1 : 0,
            result_code   => $resp_validation->{'ResponseCode'},
            error_message => $resp_validation->{'Message'},
            authorization => $resp_validation->{'AuthCode'},
            avs_code      => $resp_validation->{'AVSResult'},
            cvv2_response => $resp_validation->{'Card Validation Result'},
        );
        $sale_resp{ $account->{'OrderId'} } = $tx->order_number if $tx->is_success;
    }
}

print '-'x70;
print "CAPTURE\n";

my %cap_resp = ();
%content = %orig_content;

foreach my $account ( @{$data->{'account'}} ){
    next if $account->{'OrderId'} > 5; #can only capture first 5
    $content{'action'} = 'Post Authorization';
    $content{'amount'} = $account->{'Amount'};
    $content{'invoice_number'} = $account->{'OrderId'};
    $content{'order_number'} = $auth_resp{ $account->{'OrderId'} };

    ## get the response validation set for this order
    my ($resp_validation) = grep { $_->{'OrderId'} ==  $account->{'OrderId'} } @{ $data->{'capture'} };
    #print Dumper(\%content);
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        tx_check(
            $tx,
            desc          => "Capture",
            is_success    => $resp_validation->{'Message'} eq 'Approved' ? 1 : 0,
            result_code   => $resp_validation->{'ResponseCode'},
            error_message => $resp_validation->{'Message'},
        );
        $cap_resp{ $account->{'OrderId'} } = $tx->order_number if $tx->is_success;
    }
}

print '-'x70;
print "CREDIT\n";

%content = %orig_content;
#$content{'order_number'} = $sale_resp{ $account->{'OrderId'} } if $account->{'OrderId'} == 6;
foreach my $account ( @{$data->{'account'}} ){
    next if $account->{'OrderId'} > 5;
    $content{'action'} = 'Credit';
    $content{'amount'} = $account->{'Amount'};
    $content{'invoice_number'} = $account->{'OrderId'};
    $content{'order_number'} = $cap_resp{ $account->{'OrderId'} };

    ## get the response validation set for this order
    my ($resp_validation) = grep { $_->{'OrderId'} ==  $account->{'OrderId'} } @{ $data->{'credit_response'} };
    #print Dumper(\%content);
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        tx_check(
            $tx,
            desc          => "Credits",
            is_success    => $resp_validation->{'Message'} eq 'Approved' ? 1 : 0,
            result_code   => $resp_validation->{'ResponseCode'},
            error_message => $resp_validation->{'Message'},
        );
    }
}

print '-'x70;
print "VOID\n";

%content = %orig_content;
foreach my $account ( @{$data->{'account'}} ){
    next if $account->{'OrderId'} > 5;
    $content{'action'} = 'Void';
    $content{'amount'} = $account->{'Amount'};
    $content{'invoice_number'} = $account->{'OrderId'};
    ## void from the sales tests, so they are active, and we can do the 6th test
    $content{'order_number'} = $sale_resp{ $account->{'OrderId'} } if $sale_resp{ $account->{'OrderId'} };

    ## get the response validation set for this order
    my ($resp_validation) = grep { $_->{'OrderID'} ==  $account->{'OrderId'} } @{ $data->{'void_response'} };
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        tx_check(
            $tx,
            desc          => "Void",
            is_success    => $resp_validation->{'Message'} eq 'Approved' ? 1 : 0,
            result_code   => $resp_validation->{'Response Code'},
            error_message => $resp_validation->{'Message'},
        );
    }
}


print '-'x70;
print "Response Codes\n";

%content = %orig_content;
foreach my $account ( @{$data->{'response_codes'}} ){
    $content{'action'} = 'Authorization Only';
    $content{'amount'} = '50.00';
    $content{'invoice_number'} = time;
    $content{'card_number'} = $account->{'Account Number'};
    $content{'type'} = 'CC';

    #### exp date hack for response, this one test requires it
    if( $account->{'Account Number'} eq '4457000200000008'){
        $content{'expiration'} = '21/20'; #impossible, but formatted correctly date
    }

    ## get the response validation set for this order
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        $account->{'Approval Code'} = undef if $account->{'Approval Code'} eq 'NA';
        tx_check(
            $tx,
            desc          => "Response Codes",
            is_success    => $account->{'Message'} eq 'Approved' ? 1 : 0,
            result_code   => $account->{'Response Code'},
            error_message => $account->{'Message'},
            authorization => $account->{'Approval Code'},
        );
    }
}

print '-'x70;
print "AVS/Validation Tests\n";

%content = %orig_content;
foreach my $account ( @{$data->{'avs_validation'}} ){
    $content{'action'} = 'Authorization Only';
    $content{'amount'} = '50.00';
    $content{'invoice_number'} = time;
    $content{'card_number'} = $account->{'Account Number'};
    $content{'type'} = 'CC';

    ## get the response validation set for this order
    {
        my $tx = Business::OnlinePayment->new("Litle", @opts);
        $tx->content(%content);
        tx_check(
            $tx,
            desc          => "avs testing",
            is_success    => 1,
            result_code   => '000',
            error_message => 'Approved',
            authorization => '654321',
            avs_code      => $account->{'AVS Response Code'},
            cvv2_response => $account->{'Card Validation'},

        );
    }
}
print '-'x70;
print "3DS Responses\n";
print "################# NOT Supported yet\n";

%content = %orig_content;
################# NOT Supported yet
#$content{'3ds'} = 'BwABBJQ1AgAAAAAgJDUCAAAAAAA=';
#delete( $content{'cvv2'} );
#
#foreach my $account ( @{$data->{'3ds_response'}} ){
#    $content{'action'} = 'Authorization Only';
#    $content{'amount'} = '50.00';
#    $content{'invoice_number'} = time;
#    $content{'card_number'} = $account->{'Account Number'};
#    $content{'type'} = 'CC';
#
#    ## get the response validation set for this order
#    {
#        my $tx = Business::OnlinePayment->new("Litle", @opts);
#        $tx->content(%content);
#        $account->{'Approval Code'} = undef if $account->{'Approval Code'} eq 'NA';
#        tx_check(
#            $tx,
#            desc          => "valid card_number",
#            is_success    => $account->{'Message'} eq 'Approved' ? 1 : 0,
#            result_code   => $account->{'Response Code'},
#            error_message => $account->{'Message'},
#            authorization => $account->{'Approval Code'},
#        );
#    }
#}

done_testing;

#-----------------------------------------------------------------------------------
#
sub tx_check {
    my $tx = shift;
    my %o  = @_;

    $tx->test_transaction(1);
    $tx->submit;

    is( $tx->is_success,    $o{is_success},    "$o{desc}: " . tx_info($tx) );
    is( $tx->result_code,   $o{result_code},   "result_code(): RESULT" );
    is( $tx->error_message, $o{error_message}, "error_message() / RESPMSG" );
    if( $o{authorization} ){
        is( $tx->authorization, $o{authorization}, "authorization() / AUTHCODE" );
    }
    if( $o{avs_code} ){
        is( $tx->avs_code,  $o{avs_code},  "avs_code() / AVSADDR and AVSZIP" );
    }
    if( $o{cvv2_response} ){
        is( $tx->cvv2_response, $o{cvv2_response}, "cvv2_response() / CVV2MATCH" );
    }
    like( $tx->order_number, qr/^\w{5,19}/, "order_number() / PNREF" );
}

sub tx_info {
    my $tx = shift;

    no warnings 'uninitialized';

    return (
        join( "",
            "is_success(",     $tx->is_success,    ")",
            " order_number(",  $tx->order_number,  ")",
            " error_message(", $tx->error_message, ")",
            " result_code(",   $tx->result_code,   ")",
            " auth_info(",     $tx->authorization, ")",
            " avs_code(",      $tx->avs_code,      ")",
            " cvv2_response(", $tx->cvv2_response, ")",
        )
    );
}

sub expiration_date {
    my($month, $year) = (localtime)[4,5];
    $year++;       # So we expire next year.
    $year %= 100;  # y2k?  What's that?

    return sprintf("%02d%02d", $month, $year);
}
