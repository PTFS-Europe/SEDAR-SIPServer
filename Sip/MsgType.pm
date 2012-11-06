#
# Copyright (C) 2006-2008  Georgia Public Library Service
# 
# Author: David J. Fiander
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public
# License as published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA 02111-1307 USA
#
# Sip::MsgType.pm
#
# A Class for handing SIP messages
#

package Sip::MsgType;

use strict;
use warnings;
use Exporter;
use Sys::Syslog qw(syslog);
use UNIVERSAL qw(can);

use Sip qw(:all);
use Sip::Constants qw(:all);
use Sip::Checksum qw(verify_cksum);

use Data::Dumper;

our (@ISA, @EXPORT_OK, $VERSION);

@ISA = qw(Exporter);
@EXPORT_OK = qw(handle);
$VERSION = 0.02;

# Predeclare handler subroutines
use subs qw(handle_patron_status handle_checkout handle_checkin
	    handle_block_patron handle_sc_status handle_request_acs_resend
	    handle_login handle_patron_info handle_end_patron_session
	    handle_fee_paid handle_item_information handle_item_status_update
	    handle_patron_enable handle_hold handle_renew handle_renew_all);

#
# For the most part, Version 2.00 of the protocol just adds new
# variable fields, but sometimes it changes the fixed header.
#
# In general, if there's no '2.00' protocol entry for a handler, that's
# because 2.00 didn't extend the 1.00 version of the protocol.  This will
# be handled by the module initialization code following the declaration,
# which goes through the handlers table and creates a '2.00' entry that
# points to the same place as the '1.00' entry.  If there's a 2.00 entry
# but no 1.00 entry, then that means that it's a completely new service
# in 2.00, so 1.00 shouldn't recognize it.

my %handlers = (
		(PATRON_STATUS_REQ) => {
		    name => "Patron Status Request",
		    handler => \&handle_patron_status,
		    protocol => {
			1 => {
			    template => "A3A18",
			    template_len => 21,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_TERMINAL_PWD), (FID_PATRON_PWD)],
			}
		    }
		},
		(CHECKOUT) => {
		    name => "Checkout",
		    handler => \&handle_checkout,
		    protocol => {
			1 => {
			    template => "CCA18A18",
			    template_len => 38,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_ITEM_ID), (FID_TERMINAL_PWD)],
			},
			2 => {
			    template => "CCA18A18",
			    template_len => 38,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_ITEM_ID), (FID_TERMINAL_PWD),
				       (FID_ITEM_PROPS), (FID_PATRON_PWD),
				       (FID_FEE_ACK), (FID_CANCEL)],
			},
		    }
		},
		(CHECKIN) => {
		    name => "Checkin",
		    handler => \&handle_checkin,
		    protocol => {
			1 => {
			    template => "CA18A18",
			    template_len => 37,
			    fields => [(FID_CURRENT_LOCN), (FID_INST_ID),
				       (FID_ITEM_ID), (FID_TERMINAL_PWD)],
			},
			2 => {
			    template => "CA18A18",
			    template_len => 37,
			    fields => [(FID_CURRENT_LOCN), (FID_INST_ID),
				       (FID_ITEM_ID), (FID_TERMINAL_PWD),
				       (FID_ITEM_PROPS), (FID_CANCEL)],
			}
		    }
		},
		(BLOCK_PATRON) => {
		    name => "Block Patron",
		    handler => \&handle_block_patron,
		    protocol => {
			1 => {
			    template => "CA18",
			    template_len => 19,
			    fields => [(FID_INST_ID), (FID_BLOCKED_CARD_MSG),
				       (FID_PATRON_ID), (FID_TERMINAL_PWD)],
			},
		    }
		},
		(SC_STATUS) => {
		    name => "SC Status",
		    handler => \&handle_sc_status,
		    protocol => {
			1 => {
			    template =>"CA3A4",
			    template_len => 8,
			    fields => [],
			}
		    }
		},
		(REQUEST_ACS_RESEND) => {
		    name => "Request ACS Resend",
		    handler => \&handle_request_acs_resend,
		    protocol => {
			1 => {
			    template => "",
			    template_len => 0,
			    fields => [],
			}
		    }
		},
		(LOGIN) => {
		    name => "Login",
		    handler => \&handle_login,
		    protocol => {
			2 => {
			    template => "A1A1",
			    template_len => 2,
			    fields => [(FID_LOGIN_UID), (FID_LOGIN_PWD),
				       (FID_LOCATION_CODE)],
			}
		    }
		},
		(PATRON_INFO) => {
		    name => "Patron Info",
		    handler => \&handle_patron_info,
		    protocol => {
			2 => {
			    template => "A3A18A10",
			    template_len => 31,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_TERMINAL_PWD), (FID_PATRON_PWD),
				       (FID_START_ITEM), (FID_END_ITEM)],
			}
		    }
		},
		(END_PATRON_SESSION) => {
		    name => "End Patron Session",
		    handler => \&handle_end_patron_session,
		    protocol => {
			2 => {
			    template => "A18",
			    template_len => 18,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_TERMINAL_PWD), (FID_PATRON_PWD)],
			}
		    }
		},
		(FEE_PAID) => {
		    name => "Fee Paid",
		    handler => \&handle_fee_paid,
		    protocol => {
			2 => {
			    template => "A18A2A2A3",
			    template_len => 25,
			    fields => [(FID_FEE_AMT), (FID_INST_ID),
				       (FID_PATRON_ID), (FID_TERMINAL_PWD),
				       (FID_PATRON_PWD), (FID_FEE_ID),
				       (FID_TRANSACTION_ID)],
			}
		    }
		},
		(ITEM_INFORMATION) => {
		    name => "Item Information",
		    handler => \&handle_item_information,
		    protocol => {
			2 => {
			    template => "A18",
			    template_len => 18,
			    fields => [(FID_INST_ID), (FID_ITEM_ID),
				       (FID_TERMINAL_PWD)],
			}
		    }
		},
		(ITEM_STATUS_UPDATE) => {
		    name => "Item Status Update",
		    handler => \&handle_item_status_update,
		    protocol => {
			2 => {
			    template => "A18",
			    template_len => 18,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_ITEM_ID), (FID_TERMINAL_PWD),
				       (FID_ITEM_PROPS)],
			}
		    }
		},
		(PATRON_ENABLE) => {
		    name => "Patron Enable",
		    handler => \&handle_patron_enable,
		    protocol => {
			2 => {
			    template => "A18",
			    template_len => 18,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_TERMINAL_PWD), (FID_PATRON_PWD)],
			}
		    }
		},
		(HOLD) => {
		    name => "Hold",
		    handler => \&handle_hold,
		    protocol => {
			2 => {
			    template => "AA18",
			    template_len => 19,
			    fields => [(FID_EXPIRATION), (FID_PICKUP_LOCN),
				       (FID_HOLD_TYPE), (FID_INST_ID),
				       (FID_PATRON_ID), (FID_PATRON_PWD),
				       (FID_ITEM_ID), (FID_TITLE_ID),
				       (FID_TERMINAL_PWD), (FID_FEE_ACK)],
			}
		    }
		},
		(RENEW) => {
		    name => "Renew",
		    handler => \&handle_renew,
		    protocol => {
			2 => {
			    template => "CCA18A18",
			    template_len => 38,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_PATRON_PWD), (FID_ITEM_ID),
				       (FID_TITLE_ID), (FID_TERMINAL_PWD),
				       (FID_ITEM_PROPS), (FID_FEE_ACK)],
			}
		    }
		},
		(RENEW_ALL) => {
		    name => "Renew All",
		    handler => \&handle_renew_all,
		    protocol => {
			2 => {
			    template => "A18",
			    template_len => 18,
			    fields => [(FID_INST_ID), (FID_PATRON_ID),
				       (FID_PATRON_PWD), (FID_TERMINAL_PWD),
				       (FID_FEE_ACK)],
			}
		    }
		}
		);

#
# Now, initialize some of the missing bits of %handlers
#
foreach my $i (keys(%handlers)) {
    if (!exists($handlers{$i}->{protocol}->{2})) {

	$handlers{$i}->{protocol}->{2} = $handlers{$i}->{protocol}->{1};
    }
}

sub new {
    my ($class, $msg, $seqno) = @_;
    my $self = {};
    my $msgtag = substr($msg, 0, 2);

    syslog("LOG_DEBUG", "Sip::MsgType::new('%s', '%s', '%s'): msgtag '%s'",
	   $class, substr($msg, 0, 10), $msgtag, $seqno);
    if ($msgtag eq LOGIN) {
	# If the client is using the 2.00-style "Login" message
	# to authenticate to the server, then we get the Login message
	# _before_ the client has indicated that it supports 2.00, but
	# it's using the 2.00 login process, so it must support 2.00,
	# so we'll just do it.
	$protocol_version = 2;
    }
    if (!exists($handlers{$msgtag})) {
	syslog("LOG_WARNING",
	       "new Sip::MsgType: Skipping message of unknown type '%s' in '%s'",
	       $msgtag, $msg);
	return(undef);
    } elsif (!exists($handlers{$msgtag}->{protocol}->{$protocol_version})) {
	syslog("LOG_WARNING", "new Sip::MsgType: Skipping message '%s' unsupported by protocol rev. '%d'",
	       $msgtag, $protocol_version);
	return(undef);
    }

    bless $self, $class;

    $self->{seqno} = $seqno;
    $self->_initialize(substr($msg,2), $handlers{$msgtag});

    return($self);
}

sub _initialize {
    my ($self, $msg, $control_block) = @_;
    my ($fs, $fn, $fe);
    my $proto = $control_block->{protocol}->{$protocol_version};

    $self->{name}    = $control_block->{name};
    $self->{handler} = $control_block->{handler};

    $self->{fields} = {};
    $self->{fixed_fields} = [];

    syslog("LOG_DEBUG", "Sip::MsgType::_initialize('%s', '%s...')", $self->{name}, substr($msg,0,20));


    foreach my $field (@{$proto->{fields}}) {
        $self->{fields}->{$field} = undef;
    }

    syslog("LOG_DEBUG",
	   "Sip::MsgType::_initialize('%s', '%s', '%s', '%s', ...",
	   $self->{name}, $msg, $proto->{template},
	   $proto->{template_len});

    $self->{fixed_fields} = [ unpack($proto->{template}, $msg) ];

    # Skip over the fixed fields and the split the rest of
    # the message into fields based on the delimiter and parse them
    foreach my $field (split(quotemeta($field_delimiter), substr($msg, $proto->{template_len}))) {
	$fn = substr($field, 0, 2);

	if (!exists($self->{fields}->{$fn})) {
	    syslog("LOG_WARNING",
		   "Unsupported field '%s' in %s message '%s'",
		   $fn, $self->{name}, $msg);
	} elsif (defined($self->{fields}->{$fn})) {
	    syslog("LOG_WARNING",
		   "Duplicate field '%s' (previous value '%s') in %s message '%s'",
		   $fn, $self->{fields}->{$fn}, $self->{name}, $msg);
	} else {
	    $self->{fields}->{$fn} = substr($field, 2);
	}
    }

    return($self);
}

sub handle {
    my ($msg, $server, $req) = @_;
    my $config = $server->{config};
    my $self;


    #
    # What's the field delimiter for variable length fields?
    # This can't be based on the account, since we need to know
    # the field delimiter to parse a SIP login message
    #
    if (defined($server->{config}->{delimiter})) {
	$field_delimiter = $server->{config}->{delimiter};
    }

    # error detection is active if this is a REQUEST_ACS_RESEND
    # message with a checksum, or if the message is long enough
    # and the last nine characters begin with a sequence number
    # field
    if ($msg eq REQUEST_ACS_RESEND_CKSUM) {
	# Special case

	$error_detection = 1;
	$self = new Sip::MsgType ((REQUEST_ACS_RESEND), 0);
    } elsif((length($msg) > 11) && (substr($msg, -9, 2) eq "AY")) {
	$error_detection = 1;

	if (!verify_cksum($msg)) {
	    syslog("LOG_WARNING", "Checksum failed on message '%s'", $msg);
	    # REQUEST_SC_RESEND with error detection
	    $last_response = REQUEST_SC_RESEND_CKSUM;
	    print("$last_response\r");
	    return REQUEST_ACS_RESEND;
	} else {
	    # Save the sequence number, then strip off the
	    # error detection data to process the message
	    $self = new Sip::MsgType (substr($msg, 0, -9), substr($msg, -7, 1));
	}
    } elsif ($error_detection) {
	# We've receive a non-ED message when ED is supposed
	# to be active.  Warn about this problem, then process
	# the message anyway.
	syslog("LOG_WARNING",
	       "Received message without error detection: '%s'", $msg);
	$error_detection = 0;
	$self = new Sip::MsgType ($msg, 0);
    } else {
	$self = new Sip::MsgType ($msg, 0);
    }

    if ((substr($msg, 0, 2) ne REQUEST_ACS_RESEND) &&
	$req && (substr($msg, 0, 2) ne $req)) {
	return substr($msg, 0, 2);
    }
    return($self->{handler}->($self, $server));
}

##
## Message Handlers
##

#
# Patron status messages are produced in response to both
# "Request Patron Status" and "Block Patron"
#
# Request Patron Status requires a patron password, but
# Block Patron doesn't (since the patron may never have
# provided one before attempting some illegal action).
# 
# ASSUMPTION: If the patron password field is present in the
# message, then it must match, otherwise incomplete patron status
# information will be returned to the terminal.
# 
sub build_patron_status {
    my ($patron, $lang, $fields)= @_;
    $lang ||= '000';
    my $patron_pwd = $fields->{(FID_PATRON_PWD)};
    my $resp = (PATRON_STATUS_RESP);

    if ($patron) {
	$resp .= patron_status_string($patron);
	$resp .= $lang . Sip::timestamp();
	$resp .= add_field(FID_PERSONAL_NAME, $patron->name);

	# while the patron ID we got from the SC is valid, let's
	# use the one returned from the ILS, just in case...
	$resp .= add_field(FID_PATRON_ID, $patron->id);
	if ($protocol_version >= 2) {
	    $resp .= add_field(FID_VALID_PATRON, 'Y');
	    # Patron password is a required field.
		$resp .= add_field(FID_VALID_PATRON_PWD, sipbool($patron->check_password($patron_pwd)));
	    $resp .= maybe_add(FID_CURRENCY, $patron->currency);
	    $resp .= maybe_add(FID_FEE_AMT, $patron->fee_amount);
	}

	$resp .= maybe_add(FID_SCREEN_MSG, $patron->screen_msg);
	$resp .= maybe_add(FID_PRINT_LINE, $patron->print_line);
    } else {
	# Invalid patron id.  Report that the user has no privs.,
	# no personal name, and is invalid (if we're using 2.00)
	$resp .= 'YYYY' . (' ' x 10) . $lang . Sip::timestamp();
	$resp .= add_field(FID_PERSONAL_NAME, '');

	# the patron ID is invalid, but it's a required field, so
	# just echo it back
	$resp .= add_field(FID_PATRON_ID, $fields->{(FID_PATRON_ID)});

	if ($protocol_version >= 2) {
	    $resp .= add_field(FID_VALID_PATRON, 'N');
	}
    }

    $resp .= add_field(FID_INST_ID, $fields->{(FID_INST_ID)});

    return $resp;
}

sub handle_patron_status {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($lang, $date);
    my $fields;
    my $patron;
    my $resp = (PATRON_STATUS_RESP);
    my $account = $server->{account};

    ($lang, $date) = @{$self->{fixed_fields}};
    $fields = $self->{fields};

    $ils->check_inst_id($fields->{(FID_INST_ID)}, "handle_patron_status");

    $patron = $ils->find_patron($fields->{(FID_PATRON_ID)});

    $resp = build_patron_status($patron, $lang, $fields);

    $self->write_msg($resp);

    return (PATRON_STATUS_REQ);
}

sub handle_checkout {
    my ($self, $server) = @_;
    my $account = $server->{account};
    my $ils = $server->{ils};
    my $inst = $ils->institution;
    my ($sc_renewal_policy, $no_block, $trans_date, $nb_due_date);
    my $fields;
    my ($patron_id, $item_id, $status, $fee_ack);
    my ($item, $patron);
    my $resp;

    ($sc_renewal_policy, $no_block, $trans_date, $nb_due_date) =
	@{$self->{fixed_fields}};
    $fields = $self->{fields};

    $patron_id = $fields->{(FID_PATRON_ID)};
    $item_id   = $fields->{(FID_ITEM_ID)};
    $fee_ack = $fields->{(FID_FEE_ACK)};


    if ($no_block eq 'Y') {
	# Off-line transactions need to be recorded, but there's
	# not a lot we can do about it
	syslog("LOG_WARNING", "received no-block checkout from terminal '%s'",
	       $account->{id});

	$status = $ils->checkout_no_block($patron_id, $item_id,
					  $sc_renewal_policy,
					  $trans_date, $nb_due_date);
    } else {
	# Does the transaction date really matter for items that are
	# checkout out while the terminal is online?  I'm guessing 'no'
	$status = $ils->checkout($patron_id, $item_id, $sc_renewal_policy, $fee_ack);
    }


    $item   = $status->item;
    $patron = $status->patron;

    if ($status->ok) {
	# Item successfully checked out
	# Fixed fields
	$resp = CHECKOUT_RESP . '1';
	$resp .= sipbool($status->renew_ok);
	if ($ils->supports('magnetic media')) {
	    $resp .= sipbool($item->magnetic);
	} else {
	    $resp .= 'U';
	}
	# We never return the obsolete 'U' value for 'desensitize'
	$resp .= sipbool($status->desensitize);
	$resp .= Sip::timestamp;

	# Now for the variable fields
	$resp .= add_field(FID_INST_ID,  $inst);
	$resp .= add_field(FID_PATRON_ID, $patron_id);
	$resp .= add_field(FID_ITEM_ID,  $item_id);
	$resp .= add_field(FID_TITLE_ID, $item->title_id);
	$resp .= add_field(FID_DUE_DATE, $item->due_date);

	$resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
	$resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

	if ($protocol_version >= 2) {
	    if ($ils->supports('security inhibit')) {
		$resp .= add_field(FID_SECURITY_INHIBIT, $status->security_inhibit);
	    }
	    $resp .= maybe_add(FID_MEDIA_TYPE, $item->sip_media_type);
	    $resp .= maybe_add(FID_ITEM_PROPS, $item->sip_item_properties);

	    # Financials
	    if ($status->fee_amount) {
		$resp .= add_field(FID_FEE_AMT,  $status->fee_amount);
		$resp .= maybe_add(FID_CURRENCY, $status->sip_currency);
		$resp .= maybe_add(FID_FEE_TYPE, $status->sip_fee_type);
		$resp .= maybe_add(FID_TRANSACTION_ID,
				   $status->transaction_id);
	    }
	}

    } else {
	# Checkout failed
	# Checkout Response: not ok, no renewal, don't know mag. media,
	# no desensitize
	$resp = sprintf("120%sUN%s", sipbool($status->renew_ok), Sip::timestamp);
	$resp .= add_field(FID_INST_ID, $inst);
	$resp .= add_field(FID_PATRON_ID, $patron_id);
	$resp .= add_field(FID_ITEM_ID, $item_id);

	# If the item is valid, provide the title, otherwise
	# leave it blank
	$resp .= add_field(FID_TITLE_ID, $item ? $item->title_id : '');
	# Due date is required.  Since it didn't get checked out,
	# it's not due, so leave the date blank
	$resp .= add_field(FID_DUE_DATE, '');

	$resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
	$resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

	if ($protocol_version >= 2) {
	    # Is the patron ID valid?
	    $resp .= add_field(FID_VALID_PATRON, sipbool($patron));

	    if ($patron && exists($fields->{FID_PATRON_PWD})) {
		# Password provided, so we can tell if it was valid or not
		$resp .= add_field(FID_VALID_PATRON_PWD,
				   sipbool($patron->check_password($fields->{(FID_PATRON_PWD)})));
	    }
            # For the patron to accept a fee in chargeable loans, we
            # need to return fee information.
	    if ($status->fee_amount) {
		$resp .= add_field(FID_FEE_AMT,  $status->fee_amount);
		$resp .= maybe_add(FID_CURRENCY, $status->sip_currency);
		$resp .= maybe_add(FID_FEE_TYPE, $status->sip_fee_type);
            }
	}
    }

    $self->write_msg($resp);
    return(CHECKOUT);
}

sub handle_checkin {
    my ($self, $server) = @_;
    my $account = $server->{account};
    my $ils     = $server->{ils};
    my ($current_loc, $inst_id, $item_id, $terminal_pwd, $item_props, $cancel);
    my ($patron, $item, $status);
    my $resp = CHECKIN_RESP;

    my ($no_block, $trans_date, $return_date) = @{$self->{fixed_fields}};
    my $fields = $self->{fields};

    $current_loc = $fields->{(FID_CURRENT_LOCN)};
    $inst_id     = $fields->{(FID_INST_ID)     };
    $item_id     = $fields->{(FID_ITEM_ID)     };
    $item_props  = $fields->{(FID_ITEM_PROPS)  };
    $cancel      = $fields->{(FID_CANCEL)      };

    $ils->check_inst_id($inst_id, "handle_checkin");

    if ($no_block eq 'Y') {
        # Off-line transactions, ick.
        syslog("LOG_WARNING", "received no-block checkin from terminal '%s'", $account->{id});
        $status = $ils->checkin_no_block($item_id, $trans_date, $return_date, $item_props, $cancel);
    } else {
        $status = $ils->checkin($item_id, $inst_id, $trans_date, $return_date, $current_loc, $item_props, $cancel);
    }

    $patron = $status->patron;
    $item   = $status->item;

    $resp .= $status->ok ? '1' : '0';
    $resp .= $status->resensitize ? 'Y' : 'N';
    if ($item && $ils->supports('magnetic media')) {
        $resp .= sipbool($item->magnetic);
    } else {
        # The item barcode was invalid or the system doesn't support
        # the 'magnetic media' indicator
        $resp .= 'U';
    }
    $resp .= $status->alert ? 'Y' : 'N';
    $resp .= Sip::timestamp;
    $resp .= add_field(FID_INST_ID, $inst_id);
    $resp .= add_field(FID_ITEM_ID, $item_id);

    if ($item) {
        $resp .= add_field(FID_PERM_LOCN, $item->permanent_location);
        $resp .= maybe_add(FID_TITLE_ID, $item->title_id);
    }

    if ($protocol_version >= 2) {
        $resp .= maybe_add(FID_SORT_BIN, $status->sort_bin);
        if ($patron) {
            $resp .= add_field(FID_PATRON_ID, $patron->id);
        }
        if ($item) {
            $resp .= maybe_add(FID_MEDIA_TYPE,           $item->sip_media_type     );
            $resp .= maybe_add(FID_ITEM_PROPS,           $item->sip_item_properties);
            $resp .= maybe_add(FID_COLLECTION_CODE,      $item->collection_code    );
            $resp .= maybe_add(FID_CALL_NUMBER,          $item->call_number        );
            $resp .= maybe_add(FID_DESTINATION_LOCATION, $item->destination_loc    );
            $resp .= maybe_add(FID_HOLD_PATRON_ID,       $item->hold_patron_bcode  );
            $resp .= maybe_add(FID_HOLD_PATRON_NAME,     $item->hold_patron_name   );
        }
    }

    $resp .= maybe_add(FID_ALERT_TYPE, $status->alert_type) if $status->alert;
    $resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

    $self->write_msg($resp);

    return(CHECKIN);
}

sub handle_block_patron {
    my ($self, $server) = @_;
    my $account = $server->{account};
    my $ils     = $server->{ils};
    my ($card_retained, $trans_date);
    my ($inst_id, $blocked_card_msg, $patron_id, $terminal_pwd);
    my $fields;
    my $resp;
    my $patron;

    ($card_retained, $trans_date) = @{$self->{fixed_fields}};
    $fields = $self->{fields};
    $inst_id          = $fields->{(FID_INST_ID)};
    $blocked_card_msg = $fields->{(FID_BLOCKED_CARD_MSG)};
    $patron_id        = $fields->{(FID_PATRON_ID)};
    $terminal_pwd     = $fields->{(FID_TERMINAL_PWD)};

    # Terminal passwords are different from account login
    # passwords, but I have no idea what to do with them.  So,
    # I'll just ignore them for now.

    $ils->check_inst_id($inst_id, "block_patron");

    $patron = $ils->find_patron($patron_id);

    # The correct response for a "Block Patron" message is a
    # "Patron Status Response", so use that handler to generate
    # the message, but then return the correct code from here.
    #
    # Normally, the language is provided by the "Patron Status"
    # fixed field, but since we're not responding to one of those
    # we'll just say, "Unspecified", as per the spec.  Let the
    # terminal default to something that, one hopes, will be
    # intelligible
    my $language = $patron ? $patron->language : '000';
    if ($patron) {
        # Valid patron id
        $patron->block($card_retained, $blocked_card_msg);
    }

    $resp = build_patron_status($patron, $language, $fields);

    $self->write_msg($resp);
    return(BLOCK_PATRON);
}

sub handle_sc_status {
    my ($self, $server) = @_;
    my ($status, $print_width, $sc_protocol_version, $new_proto);

    ($status, $print_width, $sc_protocol_version) = @{$self->{fixed_fields}};

    if ($sc_protocol_version =~ /^1\./) {
	$new_proto = 1;
    } elsif ($sc_protocol_version =~ /^2\./) {
	$new_proto = 2;
    } else {
	syslog("LOG_WARNING", "Unrecognized protocol revision '%s', falling back to '1'", $sc_protocol_version);
	$new_proto = 1;
    }

    if ($new_proto != $protocol_version) {
	syslog("LOG_INFO", "Setting protocol level to $new_proto");
	$protocol_version = $new_proto;
    }

    if ($status == SC_STATUS_PAPER) {
	syslog("LOG_WARNING", "Self-Check unit '%s@%s' out of paper",
	       $self->{account}->{id}, $self->{account}->{institution});
    } elsif ($status == SC_STATUS_SHUTDOWN) {
	syslog("LOG_WARNING", "Self-Check unit '%s@%s' shutting down",
	       $self->{account}->{id}, $self->{account}->{institution});
    }

    $self->{account}->{print_width} = $print_width;

    return send_acs_status($self, $server) ? SC_STATUS : '';
}

sub handle_request_acs_resend {
    my ($self, $server) = @_;

    if (!$last_response) {
        # We haven't sent anything yet, so respond with a
        # REQUEST_SC_RESEND msg (p. 16)
        $self->write_msg(REQUEST_SC_RESEND);
    } elsif ((length($last_response) < 9)
	       || substr($last_response, -9, 2) ne 'AY') {
        # When resending a message, we aren't supposed to include
        # a sequence number, even if the original had one (p. 4).
        # If the last message didn't have a sequence number, then
        # we can just send it.
        print("$last_response\r");
    } else {
        # Cut out the sequence number and checksum, since the old
        # checksum is wrong for the resent message.
        $self->write_msg(substr($last_response, 0, -9));
    }
    return REQUEST_ACS_RESEND;
}

sub handle_login {
    my ($self, $server) = @_;
    my ($uid_algorithm, $pwd_algorithm);
    my ($uid, $pwd);
    my $inst;
    my $fields;
    my $status = 1;		# Assume it all works

    $fields = $self->{fields};
    ($uid_algorithm, $pwd_algorithm) = @{$self->{fixed_fields}};

    $uid = $fields->{(FID_LOGIN_UID)};
    $pwd = $fields->{(FID_LOGIN_PWD)};

    if ($uid_algorithm || $pwd_algorithm) {
        syslog("LOG_ERR", "LOGIN: Can't cope with non-zero encryption methods: uid = $uid_algorithm, pwd = $pwd_algorithm");
        $status = 0;
    }

    if (!exists($server->{config}->{accounts}->{$uid})) {
        syslog("LOG_WARNING", "MsgType::handle_login: Unknown login '$uid'");
        $status = 0;
    } elsif ($server->{config}->{accounts}->{$uid}->{password} ne $pwd) {
        syslog("LOG_WARNING", "MsgType::handle_login: Invalid password for login '$uid'");
        $status = 0;
    } else {
        # Store the active account someplace handy for everybody else to find.
        $server->{account}     = $server->{config}->{accounts}->{$uid};
        $inst                  = $server->{account}->{institution};
        $server->{institution} = $server->{config}->{institutions}->{$inst};
        $server->{policy}      = $server->{institution}->{policy};


        syslog("LOG_INFO", "Successful login for '%s' of '%s'", $server->{account}->{id}, $inst);
        #
        # initialize connection to ILS
        #
        my $module = $server->{config}->{institutions}->{$inst}->{implementation};
        $module->use;

        if ($@) {
            syslog("LOG_ERR", "%s: Loading ILS implementation '%s' for institution '%s' failed",
               $server->{service}, $module, $inst);
            die("Failed to load ILS implementation '$module'");
        }

        $server->{ils} = $module->new($server->{institution}, $server->{account});

        if (!$server->{ils}) {
            syslog("LOG_ERR", "%s: ILS connection to '%s' failed", $server->{service}, $inst);
            die("Unable to connect to ILS '$inst'");
        }
    }

    $self->write_msg(LOGIN_RESP . $status);

    return $status ? LOGIN : '';
}

#
# Build the detailed summary information for the Patron
# Information Response message based on the first 'Y' that appears
# in the 'summary' field of the Patron Information reqest.  The
# specification says that only one 'Y' can appear in that field,
# and we're going to believe it.
#
sub summary_info {
    my ($ils, $patron, $summary, $start, $end) = @_;
    my $resp = '';
    my $itemlist;
    my $summary_type;
    my ($func, $fid);
    #
    # Map from offsets in the "summary" field of the Patron Information
    # message to the corresponding field and handler
    #
    my @summary_map = (
        { func => $patron->can("hold_items"),    fid => FID_HOLD_ITEMS },
        { func => $patron->can("overdue_items"), fid => FID_OVERDUE_ITEMS },
        { func => $patron->can("charged_items"), fid => FID_CHARGED_ITEMS },
        { func => $patron->can("fine_items"),    fid => FID_FINE_ITEMS },
        { func => $patron->can("recall_items"),  fid => FID_RECALL_ITEMS },
        { func => $patron->can("unavail_holds"), fid => FID_UNAVAILABLE_HOLD_ITEMS },
    );


    if (($summary_type = index($summary, 'Y')) == -1) {
        # No detailed information required
        return '';
    }

    syslog("LOG_DEBUG", "Summary_info: index == '%d', field '%s'",
	   $summary_type, $summary_map[$summary_type]->{fid});

    $func = $summary_map[$summary_type]->{func};
    $fid  = $summary_map[$summary_type]->{fid};
    $itemlist = &$func($patron, $start, $end);

    syslog("LOG_DEBUG", "summary_info: list = (%s)", join(", ", @{$itemlist}));
    foreach my $i (@{$itemlist}) {
        $resp .= add_field($fid, $i);
    }

    return $resp;
}

sub handle_patron_info {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($lang, $trans_date, $summary) = @{$self->{fixed_fields}};
    my $fields = $self->{fields};
    my ($inst_id, $patron_id, $terminal_pwd, $patron_pwd, $start, $end);
    my ($resp, $patron, $count);

    $inst_id      = $fields->{(FID_INST_ID)};
    $patron_id    = $fields->{(FID_PATRON_ID)};
    $terminal_pwd = $fields->{(FID_TERMINAL_PWD)};
    $patron_pwd   = $fields->{(FID_PATRON_PWD)};
    $start        = $fields->{(FID_START_ITEM)};
    $end          = $fields->{(FID_END_ITEM)};

    $patron = $ils->find_patron($patron_id);

    $resp = (PATRON_INFO_RESP);
    if ($patron) {
        $resp .= patron_status_string($patron);
        $resp .= $lang . Sip::timestamp();

        $resp .= add_count('patron_info/hold_items',    scalar @{$patron->hold_items   });
        $resp .= add_count('patron_info/overdue_items', scalar @{$patron->overdue_items});
        $resp .= add_count('patron_info/charged_items', scalar @{$patron->charged_items});
        $resp .= add_count('patron_info/fine_items',    scalar @{$patron->fine_items   });
        $resp .= add_count('patron_info/recall_items',  scalar @{$patron->recall_items });
        $resp .= add_count('patron_info/unavail_holds', scalar @{$patron->unavail_holds});

        # while the patron ID we got from the SC is valid, let's
        # use the one returned from the ILS, just in case...
        $resp .= add_field(FID_PATRON_ID, $patron->id);

        $resp .= add_field(FID_PERSONAL_NAME, $patron->name);

        # TODO: add code for the fields
        #    hold items limit
        # overdue items limit
        # charged items limit
        #           fee limit

        $resp .= maybe_add(FID_CURRENCY,   $patron->currency  );
        $resp .= maybe_add(FID_FEE_AMT,    $patron->fee_amount);
        $resp .= maybe_add(FID_HOME_ADDR,  $patron->address   );
        $resp .= maybe_add(FID_EMAIL,      $patron->email_addr);
        $resp .= maybe_add(FID_HOME_PHONE, $patron->home_phone);

        # Extension requested by PINES. Report the home system for
        # the patron in the 'AQ' field. This is normally the "permanent
        # location" field for an ITEM, but it's not used in PATRON info.
        # Apparently TLC systems do this.
        $resp .= maybe_add(FID_HOME_LIBRARY, $patron->home_library);

        $resp .= summary_info($ils, $patron, $summary, $start, $end);

        $resp .= add_field(FID_VALID_PATRON, 'Y');
        if (defined($patron_pwd)) {
	        # If the patron password was provided, report on if it was right.
            $resp .= add_field(FID_VALID_PATRON_PWD,
			       sipbool($patron->check_password($patron_pwd)));
        }

        # SIP 2.0 extensions used by Envisionware
        # Other types of terminals will ignore the fields, if
        # they don't recognize the codes
        if ($patron->can('sip_expire')) {
            $resp .= maybe_add(FID_PATRON_EXPIRE, $patron->sip_expire);
        }
        $resp .= maybe_add(FID_PATRON_BIRTHDATE, $patron->sip_birthdate);
        $resp .= maybe_add(FID_PATRON_CLASS, $patron->ptype);

        # Custom protocol extension to report patron internet privileges
        $resp .= maybe_add(FID_INET_PROFILE, $patron->inet_privileges);
        $resp .= maybe_add(FID_ICAM_PROFILE, $patron->inet_privileges);

        $resp .= maybe_add(FID_PATRON_INTERNAL_ID, $patron->internal_id);   # another extension

        $resp .= maybe_add(FID_SCREEN_MSG, $patron->screen_msg);
        $resp .= maybe_add(FID_PRINT_LINE, $patron->print_line);

        # Custom ILS-defined protocol extensions
        if ($patron->can('extra_fields')) {
            my $extra_fields = $patron->extra_fields();
            foreach my $field (keys %$extra_fields) {
                foreach my $value (@{$extra_fields->{ $field }}) {
                    $resp .= maybe_add($field, $value);
                }
            }
        }
    } else {
        # Invalid patron ID
        # He has no privileges, no items associated with him,
        # no personal name, and is invalid (if we're using 2.00)
        $resp .= 'YYYY' . (' ' x 10) . $lang . Sip::timestamp();
        $resp .= '0000' x 6;
        $resp .= add_field(FID_PERSONAL_NAME, '');

        # the patron ID is invalid, but it's a required field, so
        # just echo it back
        $resp .= add_field(FID_PATRON_ID, $fields->{(FID_PATRON_ID)});

        if ($protocol_version >= 2) {
            $resp .= add_field(FID_VALID_PATRON, 'N');
        }
    }

    $resp .= add_field(FID_INST_ID, $server->{ils}->institution);

    $self->write_msg($resp);

    return(PATRON_INFO);
}

sub handle_end_patron_session {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my $trans_date;
    my $fields = $self->{fields};
    my $resp = END_SESSION_RESP;
    my ($status, $screen_msg, $print_line);

    ($trans_date) = @{$self->{fixed_fields}};

    $ils->check_inst_id($fields->{(FID_INST_ID)}, "handle_end_patron_session");

    ($status, $screen_msg, $print_line) = $ils->end_patron_session($fields->{(FID_PATRON_ID)});

    $resp .= $status ? 'Y' : 'N';
    $resp .= Sip::timestamp();

    $resp .= add_field(FID_INST_ID, $server->{ils}->institution);
    $resp .= add_field(FID_PATRON_ID, $fields->{(FID_PATRON_ID)});

    $resp .= maybe_add(FID_SCREEN_MSG, $screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $print_line);

    $self->write_msg($resp);

    return(END_PATRON_SESSION);
}

sub handle_fee_paid {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($trans_date, $fee_type, $pay_type, $currency) = @{$self->{fixed_fields}};
    my $fields = $self->{fields};
    my ($fee_amt, $inst_id, $patron_id, $terminal_pwd, $patron_pwd);
    my ($fee_id, $trans_id);
    my $status;
    my $resp = FEE_PAID_RESP;

    $fee_amt    = $fields->{(FID_FEE_AMT)};
    $inst_id    = $fields->{(FID_INST_ID)};
    $patron_id  = $fields->{(FID_PATRON_ID)};
    $patron_pwd = $fields->{(FID_PATRON_PWD)};
    $fee_id     = $fields->{(FID_FEE_ID)};
    $trans_id   = $fields->{(FID_TRANSACTION_ID)};

    $ils->check_inst_id($inst_id, "handle_fee_paid");

    $status = $ils->pay_fee($patron_id, $patron_pwd, $fee_amt, $fee_type,
			   $pay_type, $fee_id, $trans_id, $currency);

    $resp .= ($status->ok ? 'Y' : 'N') . Sip::timestamp;
    $resp .= add_field(FID_INST_ID, $inst_id);
    $resp .= add_field(FID_PATRON_ID, $patron_id);
    $resp .= maybe_add(FID_TRANSACTION_ID, $status->transaction_id);
    $resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

    $self->write_msg($resp);

    return(FEE_PAID);
}

sub handle_item_information {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my $trans_date;
    my $fields = $self->{fields};
    my $resp = ITEM_INFO_RESP;
    my $item;

    ($trans_date) = @{$self->{fixed_fields}};

    $ils->check_inst_id($fields->{(FID_INST_ID)}, "handle_item_information");

    $item = $ils->find_item($fields->{(FID_ITEM_ID)});

    if (!defined($item)) {
        # Invalid Item ID
        # "Other" circ stat, "Other" security marker, "Unknown" fee type
        $resp .= "010101";
        $resp .= Sip::timestamp;
        # Just echo back the invalid item id
        $resp .= add_field(FID_ITEM_ID, $fields->{(FID_ITEM_ID)});
        # title id is required, but we don't have one
        $resp .= add_field(FID_TITLE_ID, '');
    } else {
        # Valid Item ID, send the good stuff
        $resp .= $item->sip_circulation_status;
        $resp .= $item->sip_security_marker;
        $resp .= $item->sip_fee_type;
        $resp .= Sip::timestamp;

        $resp .= add_field(FID_ITEM_ID,  $item->id);
        $resp .= add_field(FID_TITLE_ID, $item->title_id);

        $resp .= maybe_add(FID_MEDIA_TYPE,   $item->sip_media_type);
        $resp .= maybe_add(FID_PERM_LOCN,    $item->permanent_location);
        $resp .= maybe_add(FID_CURRENT_LOCN, $item->current_location);
        $resp .= maybe_add(FID_ITEM_PROPS,   $item->sip_item_properties);

        if ($item->fee) {
            $resp .= add_field(FID_CURRENCY, $item->fee_currency);
            $resp .= add_field(FID_FEE_AMT,  $item->fee);
        }
        $resp .= maybe_add(FID_OWNER,            $item->owner);
        $resp .= maybe_add(FID_HOLD_QUEUE_LEN,   scalar @{$item->hold_queue});
        $resp .= maybe_add(FID_DUE_DATE,         $item->due_date);
        $resp .= maybe_add(FID_RECALL_DATE,      $item->recall_date);
        $resp .= maybe_add(FID_HOLD_PICKUP_DATE, $item->hold_pickup_date);
        $resp .= maybe_add(FID_DESTINATION_LOCATION, $item->destination_loc);  # Extension for AMH sorting
        $resp .= maybe_add(FID_CALL_NUMBER,      $item->call_number);          # Extension for AMH sorting
        $resp .= maybe_add(FID_SCREEN_MSG,       $item->screen_msg);
        $resp .= maybe_add(FID_PRINT_LINE,       $item->print_line);

        # Custom ILS-defined protocol extensions
        if ($item->can('extra_fields')) {
            my $extra_fields = $item->extra_fields();
            foreach my $field (keys %$extra_fields) {
                foreach my $value (@{$extra_fields->{ $field }}) {
                    $resp .= maybe_add($field, $value);
                }
            }
        }
    }

    $self->write_msg($resp);

    return(ITEM_INFORMATION);
}

sub handle_item_status_update {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($trans_date, $item_id, $terminal_pwd, $item_props);
    my $fields = $self->{fields};
    my $status;
    my $item;
    my $resp = ITEM_STATUS_UPDATE_RESP;

    ($trans_date) = @{$self->{fixed_fields}};

    $ils->check_inst_id($fields->{(FID_INST_ID)});

    $item_id    = $fields->{(FID_ITEM_ID)};
    $item_props = $fields->{(FID_ITEM_PROPS)};

    if (!defined($item_id)) {
        syslog("LOG_WARNING", "handle_item_status: received message without Item ID field");
    } else {
        $item = $ils->find_item($item_id);
    }

    if (!$item) {
        # Invalid Item ID
        $resp .= '0';
        $resp .= Sip::timestamp;
        $resp .= add_field(FID_ITEM_ID, $item_id);
    } else {
        # Valid Item ID
        $status = $item->status_update($item_props);

        $resp .= $status->ok ? '1' : '0';
        $resp .= Sip::timestamp;

        $resp .= add_field(FID_ITEM_ID,    $item->id);
        $resp .= add_field(FID_TITLE_ID,   $item->title_id);
        $resp .= maybe_add(FID_ITEM_PROPS, $item->sip_item_properties);
    }

    $resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

    $self->write_msg($resp);

    return(ITEM_STATUS_UPDATE);
}

sub handle_patron_enable {
    my ($self, $server) = @_;
    my $ils    = $server->{ils};
    my $fields = $self->{fields};
    my ($trans_date, $patron_id, $terminal_pwd, $patron_pwd);
    my ($status, $patron);
    my $resp = PATRON_ENABLE_RESP;

    ($trans_date) = @{$self->{fixed_fields}};
    $patron_id  = $fields->{(FID_PATRON_ID)};
    $patron_pwd = $fields->{(FID_PATRON_PWD)};

    syslog("LOG_DEBUG", "handle_patron_enable: patron_id: '%s', patron_pwd: '%s'",
	   $patron_id, $patron_pwd);

    $patron = $ils->find_patron($patron_id);

    if (!defined($patron)) {
        # Invalid patron ID
        $resp .= 'YYYY' . (' ' x 10) . '000' . Sip::timestamp();
        $resp .= add_field(FID_PATRON_ID, $patron_id);
        $resp .= add_field(FID_PERSONAL_NAME,    '' );
        $resp .= add_field(FID_VALID_PATRON,     'N');
        $resp .= add_field(FID_VALID_PATRON_PWD, 'N');
    } else {
        # valid patron
        if (!defined($patron_pwd) || $patron->check_password($patron_pwd)) {
            # Don't enable the patron if there was an invalid password
            $status = $patron->enable;
        }
        $resp .= patron_status_string($patron);
        $resp .= $patron->language . Sip::timestamp();

        $resp .= add_field(FID_PATRON_ID,     $patron->id);
        $resp .= add_field(FID_PERSONAL_NAME, $patron->name);
        if (defined($patron_pwd)) {
            $resp .= add_field(FID_VALID_PATRON_PWD,
                       sipbool($patron->check_password($patron_pwd)));
        }
        $resp .= add_field(FID_VALID_PATRON, 'Y');
        $resp .= maybe_add(FID_SCREEN_MSG, $patron->screen_msg);
        $resp .= maybe_add(FID_PRINT_LINE, $patron->print_line);
    }

    $resp .= add_field(FID_INST_ID, $ils->institution);

    $self->write_msg($resp);

    return(PATRON_ENABLE);
}

sub handle_hold {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($hold_mode, $trans_date);
    my ($expiry_date, $pickup_locn, $hold_type, $patron_id, $patron_pwd);
    my ($item_id, $title_id, $fee_ack);
    my $fields = $self->{fields};
    my $status;
    my $resp = HOLD_RESP;

    ($hold_mode, $trans_date) = @{$self->{fixed_fields}};

    $ils->check_inst_id($fields->{(FID_INST_ID)}, "handle_hold");

    $patron_id   = $fields->{(FID_PATRON_ID)  };
    $expiry_date = $fields->{(FID_EXPIRATION) } || '';
    $pickup_locn = $fields->{(FID_PICKUP_LOCN)} || '';
    $hold_type   = $fields->{(FID_HOLD_TYPE)  } || '2'; # Any copy of title
    $patron_pwd  = $fields->{(FID_PATRON_PWD) };
    $item_id     = $fields->{(FID_ITEM_ID)    } || '';
    $title_id    = $fields->{(FID_TITLE_ID)   } || '';
    $fee_ack     = $fields->{(FID_FEE_ACK)    } || 'N';

    if ($hold_mode eq '+') {
	$status = $ils->add_hold($patron_id, $patron_pwd,
				 $item_id, $title_id,
				 $expiry_date, $pickup_locn, $hold_type,
				 $fee_ack);
    } elsif ($hold_mode eq '-') {
	$status = $ils->cancel_hold($patron_id, $patron_pwd,
				    $item_id, $title_id);
    } elsif ($hold_mode eq '*') {
	$status = $ils->alter_hold($patron_id, $patron_pwd,
				   $item_id, $title_id,
				   $expiry_date, $pickup_locn, $hold_type,
				   $fee_ack);
    } else {
	syslog("LOG_WARNING", "handle_hold: Unrecognized hold mode '%s' from terminal '%s'",
	       $hold_mode, $server->{account}->{id});
	$status = $ils->Transaction::Hold;
	$status->screen_msg("System error. Please contact library status");
    }

    $resp .= $status->ok;
    $resp .= sipbool($status->item && $status->item->available($patron_id));
    $resp .= Sip::timestamp;

    if ($status->ok) {
	$resp .= add_field(FID_PATRON_ID, $status->patron->id);

	if ($status->expiration_date) {
	    $resp .= maybe_add(FID_EXPIRATION,
			       Sip::timestamp($status->expiration_date));
	}
	$resp .= maybe_add(FID_QUEUE_POS,   $status->queue_position);
	$resp .= maybe_add(FID_PICKUP_LOCN, $status->pickup_location);
	$resp .= maybe_add(FID_ITEM_ID,     $status->item->id);
	$resp .= maybe_add(FID_TITLE_ID,    $status->item->title_id);
    } else {
	# Not ok.  still need required fields
	$resp .= add_field(FID_PATRON_ID, $patron_id);
    }

    $resp .= add_field(FID_INST_ID, $ils->institution);
    $resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

    $self->write_msg($resp);

    return(HOLD);
}

sub handle_renew {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($third_party, $no_block, $trans_date, $nb_due_date);
    my ($patron_id, $patron_pwd, $item_id, $title_id, $item_props, $fee_ack);
    my $fields = $self->{fields};
    my $status;
    my ($patron, $item);
    my $resp = RENEW_RESP;

    ($third_party, $no_block, $trans_date, $nb_due_date) =
	@{$self->{fixed_fields}};

    $ils->check_inst_id($fields->{(FID_INST_ID)}, "handle_renew");

    if ($no_block eq 'Y') {
	syslog("LOG_WARNING",
	       "handle_renew: recieved 'no block' renewal from terminal '%s'",
	       $server->{account}->{id});
    }

    $patron_id  = $fields->{(FID_PATRON_ID)};
    $patron_pwd = $fields->{(FID_PATRON_PWD)};
    $item_id    = $fields->{(FID_ITEM_ID)};
    $title_id   = $fields->{(FID_TITLE_ID)};
    $item_props = $fields->{(FID_ITEM_PROPS)};
    $fee_ack    = $fields->{(FID_FEE_ACK)};

    $status = $ils->renew($patron_id, $patron_pwd, $item_id, $title_id,
			  $no_block, $nb_due_date, $third_party,
			  $item_props, $fee_ack);

    $patron = $status->patron;
    $item   = $status->item;

    if ($status->ok) {
	$resp .= '1';
	$resp .= $status->renewal_ok ? 'Y' : 'N';
	if ($ils->supports('magnetic media')) {
	    $resp .= sipbool($item->magnetic);
	} else {
	    $resp .= 'U';
	}
    $resp .= sipbool($status->desensitize);
    $resp .= Sip::timestamp;
    $resp .= add_field(FID_PATRON_ID, $patron->id);
    $resp .= add_field(FID_ITEM_ID,   $item->id);
    $resp .= add_field(FID_TITLE_ID,  $item->title_id);
    $resp .= add_field(FID_DUE_DATE,  $item->due_date);
    if ($ils->supports('security inhibit')) {
        $resp .= add_field(FID_SECURITY_INHIBIT, $status->security_inhibit);
    }
	$resp .= add_field(FID_MEDIA_TYPE, $item->sip_media_type);
	$resp .= maybe_add(FID_ITEM_PROPS, $item->sip_item_properties);
    } else {
	# renew failed for some reason
	# not OK, renewal not OK, Unknown media type (why bother checking?)
	$resp .= '0NUN';
	$resp .= Sip::timestamp;
	# If we found the patron or the item, the return the ILS
	# information, otherwise echo back the infomation we received
	# from the terminal
    $resp .= add_field(FID_PATRON_ID, $patron ? $patron->id     : $patron_id);
    $resp .= add_field(FID_ITEM_ID,   $item   ? $item->id       : $item_id  );
    $resp .= add_field(FID_TITLE_ID,  $item   ? $item->title_id : $title_id );
    $resp .= add_field(FID_DUE_DATE, '');
    }

    if ($status->fee_amount) {
        $resp .= add_field(FID_FEE_AMT,        $status->fee_amount);
        $resp .= maybe_add(FID_CURRENCY,       $status->sip_currency);
        $resp .= maybe_add(FID_FEE_TYPE,       $status->sip_fee_type);
        $resp .= maybe_add(FID_TRANSACTION_ID, $status->transaction_id);
    }

    $resp .= add_field(FID_INST_ID, $ils->institution);
    $resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

    $self->write_msg($resp);

    return(RENEW);
}

sub handle_renew_all {
    my ($self, $server) = @_;
    my $ils = $server->{ils};
    my ($trans_date, $patron_id, $patron_pwd, $terminal_pwd, $fee_ack);
    my $fields = $self->{fields};
    my $resp = RENEW_ALL_RESP;
    my $status;
    my (@renewed, @unrenewed);

    $ils->check_inst_id($fields->{(FID_INST_ID)}, "handle_renew_all");

    ($trans_date) = @{$self->{fixed_fields}};

    $patron_id    = $fields->{(FID_PATRON_ID)};
    $patron_pwd   = $fields->{(FID_PATRON_PWD)};
    $terminal_pwd = $fields->{(FID_TERMINAL_PWD)};
    $fee_ack      = $fields->{(FID_FEE_ACK)};

    $status = $ils->renew_all($patron_id, $patron_pwd, $fee_ack);

    $resp .= $status->ok ? '1' : '0';

    if (!$status->ok) {
	$resp .= add_count("renew_all/renewed_count", 0);
	$resp .= add_count("renew_all/unrenewed_count", 0);
	@renewed = [];
	@unrenewed = [];
    } else {
	@renewed = @{$status->renewed};
	@unrenewed = @{$status->unrenewed};
	$resp .= add_count("renew_all/renewed_count", scalar @renewed);
	$resp .= add_count("renew_all/unrenewed_count", scalar @unrenewed);
    }

    $resp .= Sip::timestamp;
    $resp .= add_field(FID_INST_ID, $ils->institution);

    $resp .= join('', map(add_field(FID_RENEWED_ITEMS, $_), @renewed));
    $resp .= join('', map(add_field(FID_UNRENEWED_ITEMS, $_), @unrenewed));

    $resp .= maybe_add(FID_SCREEN_MSG, $status->screen_msg);
    $resp .= maybe_add(FID_PRINT_LINE, $status->print_line);

    $self->write_msg($resp);

    return(RENEW_ALL);
}

#
# send_acs_status($self, $server)
#
# Send an ACS Status message, which is contains lots of little fields
# of information gleaned from all sorts of places.
#

my @message_type_names = (
			  "patron status request",
			  "checkout",
			  "checkin",
			  "block patron",
			  "acs status",
			  "request sc/acs resend",
			  "login",
			  "patron information",
			  "end patron session",
			  "fee paid",
			  "item information",
			  "item status update",
			  "patron enable",
			  "hold",
			  "renew",
			  "renew all",
			 );

sub send_acs_status {
    my ($self, $server, $screen_msg, $print_line) = @_;
    my $msg = ACS_STATUS;
    my $account = $server->{account};
    my $policy  = $server->{policy};
    my $ils     = $server->{ils};
    my ($online_status, $checkin_ok, $checkout_ok, $ACS_renewal_policy);
    my ($status_update_ok, $offline_ok, $timeout, $retries);

    $online_status = 'Y';
    $checkout_ok        = sipbool($ils->checkout_ok);
    $checkin_ok         = sipbool($ils->checkin_ok);
    $ACS_renewal_policy = sipbool($policy->{renewal});
    $status_update_ok   = sipbool($ils->status_update_ok);
    $offline_ok         = sipbool($ils->offline_ok);
    $timeout = sprintf("%03d", $policy->{timeout});
    $retries = sprintf("%03d", $policy->{retries});

    if (length($timeout) != 3) {
        syslog("LOG_ERR", "handle_acs_status: timeout field wrong size: '%s'", $timeout);
        $timeout = '000';
    }

    if (length($retries) != 3) {
        syslog("LOG_ERR", "handle_acs_status: retries field wrong size: '%s'", $retries);
        $retries = '000';
    }

    $msg .= "$online_status$checkin_ok$checkout_ok$ACS_renewal_policy";
    $msg .= "$status_update_ok$offline_ok$timeout$retries";
    $msg .= Sip::timestamp();

    if ($protocol_version == 1) {
        $msg .= '1.00';
    } elsif ($protocol_version == 2) {
        $msg .= '2.00';
    } else {
        syslog("LOG_ERR", 'Bad setting for $protocol_version, "%s" in send_acs_status', $protocol_version);
        $msg .= '1.00';
    }

    # Institution ID
    $msg .= add_field(FID_INST_ID, $account->{institution});

    if ($protocol_version >= 2) {
    # Supported messages: we do it all
    my $supported_msgs = '';

    foreach my $msg_name (@message_type_names) {
        if ( $msg_name eq 'request sc/acs resend' ) {
            $supported_msgs .= Sip::sipbool(1);
        } else {
            $supported_msgs .= Sip::sipbool( $ils->supports($msg_name) );
        }
    }
    if (length($supported_msgs) < 16) {
        syslog("LOG_ERR", 'send_acs_status: supported messages "%s" too short', $supported_msgs);
    }
        $msg .= add_field(FID_SUPPORTED_MSGS, $supported_msgs);
    }

    $msg .= maybe_add(FID_SCREEN_MSG, $screen_msg);

    if (defined($account->{print_width}) && defined($print_line)
             && $account->{print_width}  <  length( $print_line)) {
        syslog("LOG_WARNING", "send_acs_status: print line '%s' too long.  Truncating", $print_line);
        $print_line = substr($print_line, 0, $account->{print_width});
    }

    $msg .= maybe_add(FID_PRINT_LINE, $print_line);

    # Do we want to tell the terminal its location?

    $self->write_msg($msg);
    return 1;
}

#
# patron_status_string: create the 14-char patron status
# string for the Patron Status message
#
sub patron_status_string {
    my $patron = shift;
    syslog("LOG_DEBUG", "patron_status_string for %s charge_ok: %s", $patron->id, $patron->charge_ok);
    my $patron_status = sprintf('%s%s%s%s%s%s%s%s%s%s%s%s%s%s',
        denied($patron->charge_ok),
        denied($patron->renew_ok),
        denied($patron->recall_ok),
        denied($patron->hold_ok),
        boolspace($patron->card_lost),
        boolspace($patron->too_many_charged),
        boolspace($patron->too_many_overdue),
        boolspace($patron->too_many_renewal),
        boolspace($patron->too_many_claim_return),
        boolspace($patron->too_many_lost),
        boolspace($patron->excessive_fines),
        boolspace($patron->excessive_fees),
        boolspace($patron->recall_overdue),
        boolspace($patron->too_many_billed)
    );
    return $patron_status;
}

1;
