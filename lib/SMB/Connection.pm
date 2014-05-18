# SMB Perl library, Copyright (C) 2014 Mikhael Goikhman, migo@cpan.org
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use bytes;

package SMB::Connection;

use parent 'SMB';

sub new ($$;$%) {
	my $class = shift;
	my $socket = shift;
	my $id = shift || 0;
	my %options = @_;

	my $self = $class->SUPER::new(
		%options,
		socket => $socket,
		id => $id,
	);

	bless $self, $class;

	$self->msg("Connected");

	return $self;
}

sub DESTROY ($) {
	my $self = shift;

	$self->msg("Disconnected");

	$self->socket->close;
}

sub recv_command ($) {
	my $self = shift;

	my $socket = $self->socket;
	my ($len, $data);
	my $header_label = 'NetBIOS Session Service header';
	$len = $socket->read($data, 4) // 0;
	if ($len != 4) {
		$self->err("Can't read $header_label");
		return;
	}
	my ($packet_type, $packet_flags, $packet_len) = unpack('CCn', $data);
	$self->msg("$header_label type=%x flags=%x len=%u", $packet_type, $packet_flags, $packet_len);
	if ($packet_type != 0 || $packet_flags > 1)
	{
		$self->err("Only supported $header_label with type=0 flags=0|1");
		return;
	}
	$packet_len += 1 << 16 if $packet_flags;
	$len = $socket->read($data, $packet_len) // 0;
	if ($len != $packet_len) {
		$self->err("Can't read full packet (expected $packet_len, got $len bytes)");
		return;
	}
	$self->parser_set($data);

	my $smb_num = $self->parse_uint8;
	my $smb_str = $self->parse_bytes(3);
	if ($smb_str ne 'SMB' || $smb_num != 0xff && $smb_num != 0xfe) {
		$self->err("Neither SMB1 nor SMB2 signature found, giving up");
		$self->mem(chr($smb_num) . $smb_str, "Signature");
		return;
	}
	my $is_smb1 = $smb_num == 0xff;
	$self->msg("Got SMB%d", $is_smb1 ? 1 : 2);
	$self->mem($data, "Packet");

	return $is_smb1
		? $self->parse_smb1
		: $self->parse_smb2;
}

sub log ($$$) {
	my $self = shift;
	my $is_err = shift;
	my $format = shift;
	return if $self->{disable_log};
	my $addr = $self->socket->peerhost();
	my $port = $self->socket->peerport();
	$format =~ s/(\s+\(|$)/ - client #$self->{id} [$addr:$port]$1/;
	$self->SUPER::log($is_err, $format, @_);
}

1;