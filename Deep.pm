package DBM::Deep;

##
# DBM::Deep
#
# Description:
#	Multi-level database module for storing hash trees, arrays and simple
#	key/value pairs into FTP-able, cross-platform binary database files.
#
#	Type `perldoc DBM::Deep` for complete documentation.
#
# Usage Examples:
#	my %db;
#	tie %db, 'DBM::Deep', 'my_database.db'; # standard tie() method
#	
#	my $db = new DBM::Deep( 'my_database.db' ); # preferred OO method
#
#	$db->{my_scalar} = 'hello world';
#	$db->{my_hash} = { larry => 'genius', hashes => 'fast' };
#	$db->{my_array} = [ 1, 2, 3, time() ];
#	$db->{my_complex} = [ 'hello', { perl => 'rules' }, 42, 99 ];
#	push @{$db->{my_array}}, 'another value';
#	my @key_list = keys %{$db->{my_hash}};
#	print "This module " . $db->{my_complex}->[1]->{perl} . "!\n";
#
# Copyright:
#	(c) 2002-2004 Joseph Huckaby.  All Rights Reserved.
#	This program is free software; you can redistribute it and/or 
#	modify it under the same terms as Perl itself.
##

use strict;
use FileHandle;
use Fcntl qw/:flock/;
use Digest::MD5 qw/md5/;
use UNIVERSAL qw/isa/;
use vars qw/$VERSION/;

$VERSION = "0.8";

##
# Set to 4 and 'N' for 32-bit offset tags (default).  Theoretical limit of 4 GB per file.
#	(Perl must be compiled with largefile support for files > 2 GB)
#
# Set to 8 and 'Q' for 64-bit offsets.  Theoretical limit of 16 XB per file.
#	(Perl must be compiled with largefile and 64-bit long support)
##
my $LONG_SIZE = 4;
my $LONG_PACK = 'N';

##
# Set to 4 and 'N' for 32-bit data length prefixes.  Limit of 4 GB for each key/value.
# Upgrading this is possible (see above) but probably not necessary.  If you need
# more than 4 GB for a single key or value, this module is really not for you :-)
##
my $DATA_LENGTH_SIZE = 4;
my $DATA_LENGTH_PACK = 'N';

##
# Maximum number of buckets per list before another level of indexing is done.
# Increase this value for slightly greater speed, but larger database files.
# DO NOT decrease this value below 16, due to risk of recursive reindex overrun.
##
my $MAX_BUCKETS = 16;

##
# Better not adjust anything below here, unless you're me :-)
##

##
# Precalculate index and bucket sizes based on values above.
##
my $HASH_SIZE = 16;
my $INDEX_SIZE = 256 * $LONG_SIZE;
my $BUCKET_SIZE = $HASH_SIZE + $LONG_SIZE;
my $BUCKET_LIST_SIZE = $MAX_BUCKETS * $BUCKET_SIZE;

##
# Setup file and tag signatures.  These should never change.
##
my $SIG_FILE =  'DPDB';
my $SIG_HASH =  'H';
my $SIG_ARRAY = 'A';
my $SIG_NULL =  'N';
my $SIG_DATA =  'D';
my $SIG_INDEX = 'I';
my $SIG_BLIST = 'B';
my $SIG_SIZE =  1;

##
# Setup constants for users to pass to new()
##
sub TYPE_HASH { return $SIG_HASH; }
sub TYPE_ARRAY { return $SIG_ARRAY; }

sub new {
	##
	# Class constructor method for Perl OO interface.
	# Calls tie() and returns blessed reference to tied hash or array,
	# providing a hybrid OO/tie interface.
	##
	my $class = shift;
	my $args;
	if (scalar(@_) > 1) { $args = {@_}; }
	else { $args = { file => shift }; }
	
	##
	# Check if we want a tied hash or array.
	##
	my $self;
	if (defined($args->{type}) && $args->{type} eq $SIG_ARRAY) {
		tie @$self, $class, %$args;
	}
	else {
		tie %$self, $class, %$args;
	}

	return bless $self, $class;
}

sub init {
	##
	# Setup $self and bless into this class.
	##
	my $class = shift;
	my $args = shift;
	
	my $self = {
		type => $args->{type} || $SIG_HASH,
		base_offset => $args->{base_offset} || length($SIG_FILE),
		root => $args->{root} || {
			file => $args->{file} || undef,
			fh => undef,
			end => 0,
			links => 0,
			autoflush => $args->{autoflush} || undef,
			locking => $args->{locking} || undef,
			volatile => $args->{volatile} || undef,
			debug => $args->{debug} || undef,
			mode => $args->{mode} || 'w+',
			locked => 0
		}
	};
	$self->{root}->{links}++;
	
	bless $self, $class;
	
	if (!defined($self->{root}->{fh})) { $self->open(); }

	return $self;
}

sub TIEHASH {
	##
	# Tied hash constructor method, called by Perl's tie() function.
	##
	my $class = shift;
	my $args;
	if (scalar(@_) > 1) { $args = {@_}; }
	else { $args = { file => shift }; }
	
	return $class->init($args);
}

sub TIEARRAY {
	##
	# Tied array constructor method, called by Perl's tie() function.
	##
	my $class = shift;
	my $args;
	if (scalar(@_) > 1) { $args = {@_}; }
	else { $args = { file => shift }; }
	
	return $class->init($args);
}

sub DESTROY {
	##
	# Class deconstructor.  Close file handle if there are no more refs.
	##
	my $self = tied( %{$_[0]} ) || return;
	
	$self->{root}->{links}--;
	
	if (!$self->{root}->{links}) {
		$self->close();
	}
}

sub open {
	##
	# Open a FileHandle to the database, create if nonexistent.
	# Make sure file signature matches DeepDB spec.
	##
	my $self = tied( %{$_[0]} ) || $_[0];

	if (defined($self->{root}->{fh})) { $self->close(); }
	
	$self->{root}->{fh} = new FileHandle $self->{root}->{file}, $self->{root}->{mode};
	if (defined($self->{root}->{fh})) {
		binmode $self->{root}->{fh}; # for win32
		if ($self->{root}->{autoflush}) { $self->{root}->{fh}->autoflush(); }
		
		my $signature;
		seek($self->{root}->{fh}, 0, 0);
		my $bytes_read = $self->{root}->{fh}->read($signature, length($SIG_FILE));
		
		##
		# File is empty -- write signature and master index
		##
		if (!$bytes_read) {
			seek($self->{root}->{fh}, 0, 0);
			$self->{root}->{fh}->print($SIG_FILE);
			$self->{root}->{end} = length($SIG_FILE);
			$self->create_tag($self->{base_offset}, $self->{type}, chr(0) x $INDEX_SIZE);
			$signature = $SIG_FILE;
			$self->{root}->{fh}->flush();
		}
		
		##
		# Check signature was valid
		##
		if ($signature eq $SIG_FILE) {
			$self->{root}->{end} = (stat($self->{root}->{fh}))[7];
			
			##
			# Get our type from master index signature
			##
			my $tag = $self->load_tag($self->{base_offset});
			$self->{type} = $tag->{signature};
			
			return 1;
		}
		else {
			$self->close();
			$self->throw_error("Signature not found -- file is not a Deep DB");
		}
	}
	else {
		$self->throw_error("Cannot open file: $!");
	}
	
	return undef;
}

sub close {
	##
	# Close database FileHandle
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	undef $self->{root}->{fh};
}

sub create_tag {
	##
	# Given offset, signature and content, create tag and write to disk
	##
	my ($self, $offset, $sig, $content) = @_;
	my $size = length($content);
	
	seek($self->{root}->{fh}, $offset, 0);
	$self->{root}->{fh}->print( $sig . pack($DATA_LENGTH_PACK, $size) . $content );
	
	if ($offset == $self->{root}->{end}) {
		$self->{root}->{end} += $SIG_SIZE + $DATA_LENGTH_SIZE + $size;
	}
	
	return {
		signature => $sig,
		size => $size,
		offset => $offset + $SIG_SIZE + $DATA_LENGTH_SIZE,
		content => $content
	};
}

sub load_tag {
	##
	# Given offset, load single tag and return signature, size and data
	##
	my $self = shift;
	my $offset = shift;
	
	seek($self->{root}->{fh}, $offset, 0);
	if ($self->{root}->{fh}->eof()) { return undef; }
	
	my $sig;
	$self->{root}->{fh}->read($sig, $SIG_SIZE);
	
	my $size;
	$self->{root}->{fh}->read($size, $DATA_LENGTH_SIZE);
	$size = unpack($DATA_LENGTH_PACK, $size);
	
	my $buffer;
	$self->{root}->{fh}->read($buffer, $size);
	
	return {
		signature => $sig,
		size => $size,
		offset => $offset + $SIG_SIZE + $DATA_LENGTH_SIZE,
		content => $buffer
	};
}

sub index_lookup {
	##
	# Given index tag, lookup single entry in index and return .
	##
	my $self = shift;
	my ($tag, $index) = @_;

	my $location = unpack($LONG_PACK, substr($tag->{content}, $index * $LONG_SIZE, $LONG_SIZE) );
	if (!$location) { return undef; }
	
	return $self->load_tag( $location );
}

sub add_bucket {
	##
	# Adds one key/value pair to bucket list, given offset, MD5 digest of key,
	# plain (undigested) key and value.
	##
	my $self = shift;
	my ($tag, $md5, $plain_key, $value) = @_;
	my $keys = $tag->{content};
	my $location = 0;
	my $result = 2;
	
	##
	# Iterate through buckets, seeing if this is a new entry or a replace.
	##
	for (my $i=0; $i<$MAX_BUCKETS; $i++) {
		my $key = substr($keys, $i * $BUCKET_SIZE, $HASH_SIZE);
		my $subloc = unpack($LONG_PACK, substr($keys, ($i * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));
		if (!$subloc) {
			##
			# Found empty bucket (end of list).  Populate and exit loop.
			##
			$result = 2;
			
			$location = $self->{root}->{end};
			seek($self->{root}->{fh}, $tag->{offset} + ($i * $BUCKET_SIZE), 0);
			$self->{root}->{fh}->print( $md5 . pack($LONG_PACK, $location) );
			last;
		}
		elsif ($md5 eq $key) {
			##
			# Found existing bucket with same key.  Replace with new value.
			##
			$result = 1;
			
			seek($self->{root}->{fh}, $subloc + $SIG_SIZE, 0);
			my $size;
			$self->{root}->{fh}->read($size, $DATA_LENGTH_SIZE); $size = unpack($DATA_LENGTH_PACK, $size);
			
			##
			# If value is a hash, array, or raw value with equal or less size, we can
			# reuse the same content area of the database.  Otherwise, we have to create
			# a new content area at the EOF.
			##
			my $actual_length;
			if (isa($value, 'HASH') || isa($value, 'ARRAY')) { $actual_length = $INDEX_SIZE; }
			else { $actual_length = length($value); }
			
			if ($actual_length <= $size) {
				$location = $subloc;
			}
			else {
				$location = $self->{root}->{end};
				seek($self->{root}->{fh}, $tag->{offset} + ($i * $BUCKET_SIZE) + $HASH_SIZE, 0);
				$self->{root}->{fh}->print( pack($LONG_PACK, $location) );
			}
			last;
		}
	} # i loop
	
	##
	# If bucket didn't fit into list, split into a new index level
	##
	if (!$location) {
		seek($self->{root}->{fh}, $tag->{ref_loc}, 0);
		$self->{root}->{fh}->print( pack($LONG_PACK, $self->{root}->{end}) );
		
		my $index_tag = $self->create_tag($self->{root}->{end}, $SIG_INDEX, chr(0) x $INDEX_SIZE);
		my @offsets = ();
		
		$keys .= $md5 . pack($LONG_PACK, 0);
		
		for (my $i=0; $i<=$MAX_BUCKETS; $i++) {
			my $key = substr($keys, $i * $BUCKET_SIZE, $HASH_SIZE);
			if ($key) {
				my $old_subloc = unpack($LONG_PACK, substr($keys, ($i * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));
				my $num = ord(substr($key, $tag->{ch} + 1, 1));
				
				if ($offsets[$num]) {
					my $offset = $offsets[$num] + $SIG_SIZE + $DATA_LENGTH_SIZE;
					seek($self->{root}->{fh}, $offset, 0);
					my $subkeys;
					$self->{root}->{fh}->read($subkeys, $BUCKET_LIST_SIZE);
					
					for (my $k=0; $k<$MAX_BUCKETS; $k++) {
						my $subloc = unpack($LONG_PACK, substr($subkeys, ($k * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));
						if (!$subloc) {
							seek($self->{root}->{fh}, $offset + ($k * $BUCKET_SIZE), 0);
							$self->{root}->{fh}->print( $key . pack($LONG_PACK, $old_subloc || $self->{root}->{end}) );
							last;
						}
					} # k loop
				}
				else {
					$offsets[$num] = $self->{root}->{end};
					seek($self->{root}->{fh}, $index_tag->{offset} + ($num * $LONG_SIZE), 0);
					$self->{root}->{fh}->print( pack($LONG_PACK, $self->{root}->{end}) );
					
					my $blist_tag = $self->create_tag($self->{root}->{end}, $SIG_BLIST, chr(0) x $BUCKET_LIST_SIZE);
					
					seek($self->{root}->{fh}, $blist_tag->{offset}, 0);
					$self->{root}->{fh}->print( $key . pack($LONG_PACK, $old_subloc || $self->{root}->{end}) );
				}
			} # key is real
		} # i loop
		
		$location = $self->{root}->{end};
	} # re-index bucket list
	
	##
	# Seek to content area and store signature, value and plaintext key
	##
	if ($location) {
		my $content_length;
		seek($self->{root}->{fh}, $location, 0);
		
		##
		# Write signature based on content type, set content length and write actual value.
		##
		if (isa($value, 'HASH')) {
			$self->{root}->{fh}->print( $SIG_HASH );
			$self->{root}->{fh}->print( pack($DATA_LENGTH_PACK, $INDEX_SIZE) . chr(0) x $INDEX_SIZE );
			$content_length = $INDEX_SIZE;
		}
		elsif (isa($value, 'ARRAY')) {
			$self->{root}->{fh}->print( $SIG_ARRAY );
			$self->{root}->{fh}->print( pack($DATA_LENGTH_PACK, $INDEX_SIZE) . chr(0) x $INDEX_SIZE );
			$content_length = $INDEX_SIZE;
		}
		elsif (!defined($value)) {
			$self->{root}->{fh}->print( $SIG_NULL );
			$self->{root}->{fh}->print( pack($DATA_LENGTH_PACK, 0) );
			$content_length = 0;
		}
		else {
			$self->{root}->{fh}->print( $SIG_DATA );
			$self->{root}->{fh}->print( pack($DATA_LENGTH_PACK, length($value)) . $value );
			$content_length = length($value);
		}
		
		##
		# Plain key is stored AFTER value, as keys are typically fetched less often.
		##
		$self->{root}->{fh}->print( pack($DATA_LENGTH_PACK, length($plain_key)) . $plain_key );
		
		##
		# If this is a new content area, advance EOF counter
		##
		if ($location == $self->{root}->{end}) {
			$self->{root}->{end} += $SIG_SIZE;
			$self->{root}->{end} += $DATA_LENGTH_SIZE + $content_length;
			$self->{root}->{end} += $DATA_LENGTH_SIZE + length($plain_key);
		}
		
		##
		# If content is a hash or array, create new child DeepDB object and
		# pass each key or element to it.
		##
		if (isa($value, 'HASH')) {
			my $branch = new DBM::Deep(
				type => $SIG_HASH,
				base_offset => $location,
				root => $self->{root}
			);
			foreach my $key (keys %{$value}) {
				$branch->{$key} = $value->{$key};
			}
		} elsif (isa($value, 'ARRAY')) {
			my $branch = new DBM::Deep(
				type => $SIG_ARRAY,
				base_offset => $location,
				root => $self->{root}
			);
			my $index = 0;
			foreach my $element (@{$value}) {
				$branch->[$index] = $element;
				$index++;
			}
		}
		
		return $result;
	}
	
	return $self->throw_error("Fatal error: indexing failed -- possibly due to corruption in file");
}

sub get_bucket_value {
	##
	# Fetch single value given tag and MD5 digested key.
	##
	my $self = shift;
	my ($tag, $md5) = @_;
	my $keys = $tag->{content};
	
	##
	# Iterate through buckets, looking for a key match
	##
	for (my $i=0; $i<$MAX_BUCKETS; $i++) {
		my $key = substr($keys, $i * $BUCKET_SIZE, $HASH_SIZE);
		my $subloc = unpack($LONG_PACK, substr($keys, ($i * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));

		if (!$subloc) {
			##
			# Hit end of list, no match
			##
			return undef;
		}
		elsif ($md5 eq $key) {
			##
			# Found match -- seek to offset and read signature
			##
			my $signature;
			seek($self->{root}->{fh}, $subloc, 0);
			$self->{root}->{fh}->read($signature, $SIG_SIZE);
			
			##
			# If value is a hash or array, return new DeepDB object with correct offset
			##
			if (($signature eq $SIG_HASH) || ($signature eq $SIG_ARRAY)) {
				return new DBM::Deep(
					type => $signature,
					base_offset => $subloc,
					root => $self->{root}
				);
			}
			
			##
			# Otherwise return actual value
			##
			elsif ($signature eq $SIG_DATA) {
				my $size;
				my $value = '';
				$self->{root}->{fh}->read($size, $DATA_LENGTH_SIZE); $size = unpack($DATA_LENGTH_PACK, $size);
				if ($size) { $self->{root}->{fh}->read($value, $size); }
				return $value;
			}
			
			##
			# Key exists, but content is null
			##
			else { return undef; }
		}
	} # i loop

	return undef;
}

sub delete_bucket {
	##
	# Delete single key/value pair given tag and MD5 digested key.
	##
	my $self = shift;
	my ($tag, $md5) = @_;
	my $keys = $tag->{content};
	
	##
	# Iterate through buckets, looking for a key match
	##
	for (my $i=0; $i<$MAX_BUCKETS; $i++) {
		my $key = substr($keys, $i * $BUCKET_SIZE, $HASH_SIZE);
		my $subloc = unpack($LONG_PACK, substr($keys, ($i * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));

		if (!$subloc) {
			##
			# Hit end of list, no match
			##
			return undef;
		}
		elsif ($md5 eq $key) {
			##
			# Matched key -- delete bucket and return
			##
			seek($self->{root}->{fh}, $tag->{offset} + ($i * $BUCKET_SIZE), 0);
			$self->{root}->{fh}->print( substr($keys, ($i+1) * $BUCKET_SIZE ) );
			$self->{root}->{fh}->print( chr(0) x $BUCKET_SIZE );
			
			return 1;
		}
	} # i loop

	return undef;
}

sub bucket_exists {
	##
	# Check existence of single key given tag and MD5 digested key.
	##
	my $self = shift;
	my ($tag, $md5) = @_;
	my $keys = $tag->{content};
	
	##
	# Iterate through buckets, looking for a key match
	##
	for (my $i=0; $i<$MAX_BUCKETS; $i++) {
		my $key = substr($keys, $i * $BUCKET_SIZE, $HASH_SIZE);
		my $subloc = unpack($LONG_PACK, substr($keys, ($i * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));

		if (!$subloc) {
			##
			# Hit end of list, no match
			##
			return undef;
		}
		elsif ($md5 eq $key) {
			##
			# Matched key -- return true
			##
			return 1;
		}
	} # i loop

	return undef;
}

sub find_bucket_list {
	##
	# Locate offset for bucket list, given digested key
	##
	my $self = shift;
	my $md5 = shift;
	
	##
	# Locate offset for bucket list using digest index system
	##
	my $ch = 0;
	my $tag = $self->load_tag($self->{base_offset});
	if (!$tag) { return undef; }
	
	while ($tag->{signature} ne $SIG_BLIST) {
		$tag = $self->index_lookup($tag, ord(substr($md5, $ch, 1)));
		if (!$tag) { return undef; }
		$ch++;
	}
	
	return $tag;
}

sub traverse_index {
	##
	# Scan index and recursively step into deeper levels, looking for next key.
	##
	my $self = shift;
	my $offset = shift;
	my $ch = shift;
	my $force_return_next = shift || undef;
	
	my $tag = $self->load_tag( $offset );
	
	if ($tag->{signature} ne $SIG_BLIST) {
		my $content = $tag->{content};
		my $start;
		if ($self->{return_next}) { $start = 0; }
		else { $start = ord(substr($self->{prev_md5}, $ch, 1)); }
		
		for (my $index = $start; $index < 256; $index++) {
			my $subloc = unpack($LONG_PACK, substr($content, $index * $LONG_SIZE, $LONG_SIZE) );
			if ($subloc) {
				my $result = $self->traverse_index( $subloc, $ch + 1, $force_return_next );
				if ($result) { return $result; }
			}
		} # index loop
		
		$self->{return_next} = 1;
	} # tag is an index
	
	elsif ($tag->{signature} eq $SIG_BLIST) {
		my $keys = $tag->{content};
		if ($force_return_next) { $self->{return_next} = 1; }
		
		##
		# Iterate through buckets, looking for a key match
		##
		for (my $i=0; $i<$MAX_BUCKETS; $i++) {
			my $key = substr($keys, $i * $BUCKET_SIZE, $HASH_SIZE);
			my $subloc = unpack($LONG_PACK, substr($keys, ($i * $BUCKET_SIZE) + $HASH_SIZE, $LONG_SIZE));
	
			if (!$subloc) {
				##
				# End of bucket list -- return to outer loop
				##
				$self->{return_next} = 1;
				last;
			}
			elsif ($key eq $self->{prev_md5}) {
				##
				# Located previous key -- return next one found
				##
				$self->{return_next} = 1;
				next;
			}
			elsif ($self->{return_next}) {
				##
				# Seek to bucket location and skip over signature
				##
				seek($self->{root}->{fh}, $subloc + $SIG_SIZE, 0);
				
				##
				# Skip over value to get to plain key
				##
				my $size;
				$self->{root}->{fh}->read($size, $DATA_LENGTH_SIZE); $size = unpack($DATA_LENGTH_PACK, $size);
				if ($size) { seek($self->{root}->{fh}, $size, 1); }
				
				##
				# Read in plain key and return as scalar
				##
				my $plain_key;
				$self->{root}->{fh}->read($size, $DATA_LENGTH_SIZE); $size = unpack($DATA_LENGTH_PACK, $size);
				if ($size) { $self->{root}->{fh}->read($plain_key, $size); }
				
				return $plain_key;
			}
		} # bucket loop
		
		$self->{return_next} = 1;
	} # tag is a bucket list
	
	return undef;
}

sub get_next_key {
	##
	# Locate next key, given digested previous one
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	
	$self->{prev_md5} = $_[1] || undef;
	$self->{return_next} = 0;
	
	##
	# If the previous key was not specifed, start at the top and
	# return the first one found.
	##
	if (!$self->{prev_md5}) {
		$self->{prev_md5} = chr(0) x $HASH_SIZE;
		$self->{return_next} = 1;
	}
	
	return $self->traverse_index( $self->{base_offset}, 0 );
}

sub lock {
	##
	# If db locking is set, flock() the db file.  If called multiple
	# times before unlock(), then the same number of unlocks() must
	# be called before the lock is released.
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $type = $_[1] || LOCK_EX;
	
	if ($self->{root}->{locking}) {
		if (!$self->{root}->{locked}) { flock($self->{root}->{fh}, $type); }
		$self->{root}->{locked}++;
	}
}

sub unlock {
	##
	# If db locking is set, unlock the db file.  See note in lock()
	# regarding calling lock() multiple times.
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $type = $_[1];
	
	if ($self->{root}->{locking} && $self->{root}->{locked} > 0) {
		$self->{root}->{locked}--;
		if (!$self->{root}->{locked}) { flock($self->{root}->{fh}, LOCK_UN); }
	}
}

sub copy_node {
	##
	# Copy single level of keys or elements to new DB handle.
	# Recurse for nested structures
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $db_temp = $_[1];
	
	if ($self->{type} eq $SIG_HASH) {
		my $key = $self->first_key();
		while ($key) {
			my $value = $self->get($key);
			if (!ref($value)) { $db_temp->put($key, $value); }
			else {
				my $type = $value->type();
				if ($type eq $SIG_HASH) { $db_temp->put($key, {}); }
				else { $db_temp->put($key, []); }
				$value->copy_node( $db_temp->get($key) );
			}
			$key = $self->next_key($key);
		}
	}
	else {
		my $length = $self->length();
		for (my $index = 0; $index < $length; $index++) {
			my $value = $self->get($index);
			if (!ref($value)) { $db_temp->put($index, $value); }
			else {
				my $type = $value->type();
				if ($type eq $SIG_HASH) { $db_temp->put($index, {}); }
				else { $db_temp->put($index, []); }
				$value->copy_node( $db_temp->get($index) );
			}
		}
	}
}

sub optimize {
	##
	# Rebuild entire database into new file, then move
	# it back on top of original.
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{root}->{links} > 1) {
		return $self->throw_error("Cannot optimize: reference count is greater than 1");
	}
	
	my $db_temp = new DBM::Deep $self->{root}->{file} . '.tmp';
	if (!$db_temp) {
		return $self->throw_error("Cannot optimize: failed to open temp file: $!");
	}
	
	$self->lock();
	$self->copy_node( $db_temp );
	undef $db_temp;
	
	if (!rename $self->{root}->{file} . '.tmp', $self->{root}->{file}) {
		unlink $self->{root}->{file} . '.tmp';
		$self->unlock();
		return $self->throw_error("Optimize failed: Cannot copy temp file over original: $!");
	}
	
	$self->unlock();
	$self->close();
	$self->open();
	
	return 1;
}

sub clone {
	##
	# Make copy of object and return
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	
	return new DBM::Deep(
		type => $self->{type},
		base_offset => $self->{base_offset},
		root => $self->{root}
	);
}

##
# Accessor methods
##

sub root {
	##
	# Get access to the root structure
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	return $self->{root};
}

sub fh {
	##
	# Get access to the raw FileHandle
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	return $self->{root}->{fh};
}

sub type {
	##
	# Get type of current node ($SIG_HASH or $SIG_ARRAY)
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	return $self->{type};
}

sub error {
	##
	# Get last error string, or undef if no error
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	return $self->{root}->{error} || undef;
}

##
# Utility methods
##

sub throw_error {
	##
	# Store error string in self
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $error_text = $_[1];
	
	$self->{root}->{error} = $error_text;
	
	if ($self->{root}->{debug}) { warn "DBM::Deep: $error_text\n"; }
	
	return undef;
}

sub clear_error {
	##
	# Clear error state
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	
	undef $self->{root}->{error};
}

sub precalc_sizes {
	##
	# Precalculate index, bucket and bucket list sizes
	##
	$INDEX_SIZE = 256 * $LONG_SIZE;
	$BUCKET_SIZE = $HASH_SIZE + $LONG_SIZE;
	$BUCKET_LIST_SIZE = $MAX_BUCKETS * $BUCKET_SIZE;
}

sub set_pack {
	##
	# Set pack/unpack modes (see file header for more)
	##
	$LONG_SIZE = shift || 4;
	$LONG_PACK = shift || 'N';
	
	$DATA_LENGTH_SIZE = shift || 4;
	$DATA_LENGTH_PACK = shift || 'N';
	
	precalc_sizes();
}

##
# tie() methods (hashes and arrays)
##

sub STORE {
	##
	# Store single hash key/value or array element in database.
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $key = $_[1];
	my $value = $_[2];
	
	my $unpacked_key = $key;
	if (($self->{type} eq $SIG_ARRAY) && ($key =~ /^\d+$/)) { $key = pack($LONG_PACK, $key); }
	my $md5 = md5($key);
	
	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh}) && !$self->open()) {
		return undef;
	}
	
	##
	# Request exclusive lock for writing
	##
	$self->lock( LOCK_EX );

	##
	# If locking is enabled, set 'end' parameter again, in case another
	# DB instance appended to our file while we were unlocked.
	##
	if ($self->{root}->{locking} || $self->{root}->{volatile}) {
		$self->{root}->{end} = (stat($self->{root}->{fh}))[7];
	}
	
	##
	# Locate offset for bucket list using digest index system
	##
	my $tag = $self->load_tag($self->{base_offset});
	if (!$tag) {
		$tag = $self->create_tag($self->{base_offset}, $SIG_INDEX, chr(0) x $INDEX_SIZE);
	}
	
	my $ch = 0;
	while ($tag->{signature} ne $SIG_BLIST) {
		my $num = ord(substr($md5, $ch, 1));
		my $new_tag = $self->index_lookup($tag, $num);
		if (!$new_tag) {
			my $ref_loc = $tag->{offset} + ($num * $LONG_SIZE);
			seek($self->{root}->{fh}, $ref_loc, 0);
			$self->{root}->{fh}->print( pack($LONG_PACK, $self->{root}->{end}) );
			
			$tag = $self->create_tag($self->{root}->{end}, $SIG_BLIST, chr(0) x $BUCKET_LIST_SIZE);
			$tag->{ref_loc} = $ref_loc;
			$tag->{ch} = $ch;
			last;
		}
		else {
			my $ref_loc = $tag->{offset} + ($num * $LONG_SIZE);
			$tag = $new_tag;
			$tag->{ref_loc} = $ref_loc;
			$tag->{ch} = $ch;
		}
		$ch++;
	}
	
	##
	# Add key/value to bucket list
	##
	my $result = $self->add_bucket( $tag, $md5, $key, $value );
	
	##
	# If this object is an array, and bucket was not a replace, and key is numerical,
	# and index is equal or greater than current length, advance length variable.
	##
	if (($result == 2) && ($self->{type} eq $SIG_ARRAY) && ($unpacked_key =~ /^\d+$/) && ($unpacked_key >= $self->FETCHSIZE())) {
		$self->STORE('length', pack($LONG_PACK, $unpacked_key + 1));
	}
	
	$self->unlock();

	return $result;
}

sub FETCH {
	##
	# Fetch single value or element given plain key or array index
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $key = $_[1];
	
	if (($self->{type} eq $SIG_ARRAY) && ($key =~ /^\d+$/)) { $key = pack($LONG_PACK, $key); }
	my $md5 = md5($key);

	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh})) { $self->open(); }
	
	##
	# Request shared lock for reading
	##
	$self->lock( LOCK_SH );
	
	my $tag = $self->find_bucket_list( $md5 );
	if (!$tag) {
		$self->unlock();
		return undef;
	}
	
	##
	# Get value from bucket list
	##
	my $result = $self->get_bucket_value( $tag, $md5 );
	
	$self->unlock();
	
	return $result;
}

sub DELETE {
	##
	# Delete single key/value pair or element given plain key or array index
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $key = $_[1];
	
	my $unpacked_key = $key;
	if (($self->{type} eq $SIG_ARRAY) && ($key =~ /^\d+$/)) { $key = pack($LONG_PACK, $key); }
	my $md5 = md5($key);

	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh})) { $self->open(); }
	
	##
	# Request exclusive lock for writing
	##
	$self->lock( LOCK_EX );
	
	my $tag = $self->find_bucket_list( $md5 );
	if (!$tag) {
		$self->unlock();
		return undef;
	}
	
	##
	# Delete bucket
	##
	my $result = $self->delete_bucket( $tag, $md5 );
	
	##
	# If this object is an array and the key deleted was on the end of the stack,
	# decrement the length variable.
	##
	if ($result && ($self->{type} eq $SIG_ARRAY) && ($unpacked_key == $self->FETCHSIZE() - 1)) {
		$self->STORE('length', pack($LONG_PACK, $unpacked_key));
	}
	
	$self->unlock();
	
	return $result;
}

sub EXISTS {
	##
	# Check if a single key or element exists given plain key or array index
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	my $key = $_[1];
	
	if (($self->{type} eq $SIG_ARRAY) && ($key =~ /^\d+$/)) { $key = pack($LONG_PACK, $key); }
	my $md5 = md5($key);

	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh})) { $self->open(); }
	
	##
	# Request shared lock for reading
	##
	$self->lock( LOCK_SH );
	
	my $tag = $self->find_bucket_list( $md5 );
	
	##
	# For some reason, the built-in exists() function returns '' for false
	##
	if (!$tag) {
		$self->unlock();
		return '';
	}
	
	##
	# Check if bucket exists and return 1 or ''
	##
	my $result = $self->bucket_exists( $tag, $md5 ) || '';
	
	$self->unlock();
	
	return $result;
}

sub CLEAR {
	##
	# Clear all keys from hash, or all elements from array.
	##
	my $self = tied( %{$_[0]} ) || $_[0];

	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh})) { $self->open(); }
	
	##
	# Request exclusive lock for writing
	##
	$self->lock( LOCK_EX );
	
	seek($self->{root}->{fh}, $self->{base_offset}, 0);
	if ($self->{root}->{fh}->eof()) {
		$self->unlock();
		return undef;
	}
	
	$self->create_tag($self->{base_offset}, $self->{type}, chr(0) x $INDEX_SIZE);
	
	$self->unlock();
	
	return 1;
}

sub FIRSTKEY {
	##
	# Locate and return first key (in no particular order)
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{type} ne $SIG_HASH) {
		return $self->throw_error("FIRSTKEY method only supported for hashes");
	}

	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh})) { $self->open(); }
	
	##
	# Request shared lock for reading
	##
	$self->lock( LOCK_SH );
	
	my $result = $self->get_next_key();
	
	$self->unlock();
	
	return $result;
}

sub NEXTKEY {
	##
	# Return next key (in no particular order), given previous one
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{type} ne $SIG_HASH) {
		return $self->throw_error("NEXTKEY method only supported for hashes");
	}
	my $prev_key = $_[1];
	my $prev_md5 = md5($prev_key);

	##
	# Make sure file is open
	##
	if (!defined($self->{root}->{fh})) { $self->open(); }
	
	##
	# Request shared lock for reading
	##
	$self->lock( LOCK_SH );
	
	my $result = $self->get_next_key( $prev_md5 );
	
	$self->unlock();
	
	return $result;
}

##
# The following methods are for arrays only
##

sub FETCHSIZE {
	##
	# Return the length of the array
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("FETCHSIZE method only supported for arrays");
	}
	
	my $packed_size = $self->FETCH('length');
	if ($packed_size) { return int(unpack($LONG_PACK, $packed_size)); }
	else { return 0; } 
}

sub STORESIZE {
	##
	# Set the length of the array
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("STORESIZE method only supported for arrays");
	}
	my $new_length = $_[1];
	
	return $self->STORE('length', pack($LONG_PACK, $new_length));
}

sub POP {
	##
	# Remove and return the last element on the array
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("POP method only supported for arrays");
	}
	my $length = $self->FETCHSIZE();
	
	if ($length) {
		my $content = $self->FETCH( $length - 1 );
		$self->DELETE( $length - 1 );
		return $content;
	}
	else {
		return undef;
	}
}

sub PUSH {
	##
	# Add new element(s) to the end of the array
	##
	my $self = tied( %{$_[0]} ) || $_[0]; shift @_;
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("PUSH method only supported for arrays");
	}
	my $length = $self->FETCHSIZE();
	
	while (my $content = shift @_) {
		$self->STORE( $length, $content );
		$length++;
	}
}

sub SHIFT {
	##
	# Remove and return first element on the array.
	# Shift over remaining elements to take up space.
	##
	my $self = tied( %{$_[0]} ) || $_[0];
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("SHIFT method only supported for arrays");
	}
	my $length = $self->FETCHSIZE();
	
	if ($length) {
		my $content = $self->FETCH( 0 );
		
		##
		# Shift elements over and remove last one.
		##
		for (my $i = 0; $i < $length - 1; $i++) {
			$self->STORE( $i, $self->FETCH($i + 1) );
		}
		$self->DELETE( $length - 1 );
		
		return $content;
	}
	else {
		return undef;
	}
}

sub UNSHIFT {
	##
	# Insert new element(s) at beginning of array.
	# Shift over other elements to make space.
	##
	my $self = tied( %{$_[0]} ) || $_[0]; shift @_;
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("UNSHIFT method only supported for arrays");
	}
	my @new_elements = @_;
	my $length = $self->FETCHSIZE();
	my $new_size = scalar @new_elements;
	
	if ($length) {
		for (my $i = $length - 1; $i >= 0; $i--) {
			$self->STORE( $i + $new_size, $self->FETCH($i) );
		}
	}
	
	for (my $i = 0; $i < $new_size; $i++) {
		$self->STORE( $i, $new_elements[$i] );
	}
}

sub SPLICE {
	##
	# Splices section of array with optional new section.
	# Returns deleted section, or last element deleted in scalar context.
	##
	my $self = tied( %{$_[0]} ) || $_[0]; shift @_;
	if ($self->{type} ne $SIG_ARRAY) {
		return $self->throw_error("SPLICE method only supported for arrays");
	}
	my $length = $self->FETCHSIZE();
	
	##
	# Calculate offset and length of splice
	##
	my $offset = shift || 0;
	if ($offset < 0) { $offset += $length; }
	
	my $splice_length = shift || ($length - $offset);
	if ($splice_length < 0) { $splice_length += ($length - $offset); }
	
	##
	# Setup array with new elements, and copy out old elements for return
	##
	my @new_elements = @_;
	my $new_size = scalar @new_elements;
	
	my @old_elements = ();
	for (my $i = $offset; $i < $offset + $splice_length; $i++) {
		push @old_elements, $self->FETCH( $i );
	}
	
	##
	# Adjust array length, and shift elements to accomodate new section.
	##
	if ($new_size > $splice_length) {
		for (my $i = $length - 1; $i >= $offset + $splice_length; $i--) {
			$self->STORE( $i + ($new_size - $splice_length), $self->FETCH($i) );
		}
	}
	elsif ($new_size < $splice_length) {
		for (my $i = $offset + $splice_length; $i < $length; $i++) {
			$self->STORE( $i + ($new_size - $splice_length), $self->FETCH($i) );
		}
		for (my $i = 0; $i < $splice_length - $new_size; $i++) {
			$self->DELETE( $length - 1 );
			$length--;
		}
	}
	
	##
	# Insert new elements into array
	##
	for (my $i = $offset; $i < $offset + $new_size; $i++) {
		$self->STORE( $i, shift @new_elements );
	}
	
	##
	# Return deleted section, or last element in scalar context.
	##
	return wantarray ? @old_elements : $old_elements[-1];
}

sub EXTEND {
	##
	# Perl will call EXTEND() when the array is likely to grow.
	# We don't care, but include it for compatibility.
	##
}

##
# Public method aliases
##
sub store { return STORE(@_); }
sub put { return STORE(@_); }

sub fetch { return FETCH(@_); }
sub get { return FETCH(@_); }

sub delete { return DELETE(@_); }
sub exists { return EXISTS(@_); }
sub clear { return CLEAR(@_); }

sub first_key { return FIRSTKEY(@_); }
sub next_key { return NEXTKEY(@_); }

sub length { return FETCHSIZE(@_); }
sub pop { return POP(@_); }
sub push { return PUSH(@_); }
sub shift { return SHIFT(@_); }
sub unshift { return UNSHIFT(@_); }
sub splice { return SPLICE(@_); }

1;

__END__

=head1 NAME

DBM::Deep - A pure perl multi-level hash/array DBM

=head1 SYNOPSIS

  use DBM::Deep;
  my $db = new DBM::Deep "foo.db";
  
  $db->{key} = 'value'; # tie() style
  print $db->{key};
  
  $db->put('key', 'value'); # OO style
  print $db->get('key');
  
  # true multi-level support
  $db->{my_complex} = [
  	'hello', { perl => 'rules' }, 
  	42, 99 ];

=head1 DESCRIPTION

A very unique DBM, written in pure perl.  True multi-level
hash/array support (unlike MLDBM, which is faked),
hybrid OO / tie() interface, cross-platform FTPable files, and quite fast.
Can handle millions of keys and unlimited hash levels without significant 
slow-down.  Written from the ground-up in pure perl -- this is NOT a 
wrapper around a C-based DBM.  Out-of-the-box compatibility with Unix, 
Mac OS X and Windows.

=head1 SETUP

Construction can be done OO-style (which is the recommended way), or using 
Perl's tie() function.  Both are examined here.

=head2 OO CONSTRUCTION

The recommended way to construct a DBM::Deep object is to use the new()
method, which gets you a a blessed, tied hash or array reference.

	my $db = new DBM::Deep "foo.db";

This opens a new database handle, mapped to the file "foo.db".  If this
file does not exist, it will automatically be created.  DB files are 
opened in "w+" (read/write) mode, and the type of object returned is a
hash, unless otherwise specified (see L<OPTIONS> below).



You can pass a number of options to the constructor to specify things like
locking, autoflush, etc.  This is done by passing an inline hash:

	my $db = new DBM::Deep(
		file => "foo.db",
		locking => 1,
		autoflush => 1
	);

Notice that the filename is now specified I<inside> the hash with
the "file" parameter, as opposed to being the sole argument to the 
constructor.  This is required if any options are specified.
See L<OPTIONS> below for the complete list.



You can also start with an array instead of a hash.  For this, you must
specify the C<type> parameter:

	my $db = new DBM::Deep(
		file => "foo.db",
		type => DBM::Deep::TYPE_ARRAY
	);

B<Note:> Specifing the C<type> parameter only takes effect when beginning
a new DB file.  If you create a DBM::Deep object with an existing file, the
C<type> will be loaded from the file header.

=head2 TIE CONSTRUCTION

Alternatively, you can create a DBM::Deep handle by using Perl's built-in
tie() function.  This is not ideal, because you get only a basic, tied hash 
which is not blessed, so you can't call any functions on it.

	my %hash;
	tie %hash, "DBM::Deep", "foo.db";
	
	my @array;
	tie @array, "DBM::Deep", "bar.db";

As with the OO constructor, you can replace the DB filename parameter with
a hash containing one or more options (see L<OPTIONS> just below for the
complete list).

	tie %hash, "DBM::Deep", {
		file => "foo.db",
		locking => 1,
		autoflush => 1
	};

=head2 OPTIONS

There are a number of options that can be passed in when constructing your
DBM::Deep objects.  These apply to both the OO- and tie- based approaches.

=over

=item * file

Filename of the DB file to link the handle to.  You can pass a full absolute
filesystem path, partial path, or a plain filename if the file is in the 
current working directory.  This is a required parameter.

=item * mode

File open mode (read-only, read-write, etc.) string passed to Perl's FileHandle
module.  This is an optional parameter, and defaults to "w+" (read/write).

=item * type

This parameter specifies what type of object to create, a hash or array.  Use
one of these two constants: C<DBM::Deep::TYPE_HASH> or C<DBM::Deep::TYPE_ARRAY>.
This only takes effect when beginning a new file.  This is an optional parameter, 
and defaults to hash.

=item * locking

Specifies whether locking is to be enabled.  DBM::Deep uses Perl's Fnctl flock()
function to lock the database in exclusive mode for writes, and shared mode for
reads.  Pass any true value to enable.  This affects the base DB handle I<and any
child hashes or arrays> that use the same DB file.  This is an optional parameter,
and defaults to 0 (disabled).  See L<LOCKING> below for more.

=item * autoflush

Specifies whether autoflush is to be enabled on the underlying FileHandle.  This
obviously slows down write operations, but is required if you have multiple
processes accessing the same DB file (also consider enable I<locking> or at least
I<volatile>).  Pass any true value to enable.  This is an optional parameter,
and defaults to 0 (disabled).

=item * volatile

If I<volatile> mode is enabled, DBM::Deep will stat() the DB file before each
STORE() operation.  This is required if an outside force may change the size of
the file between transactions.  Locking also implicitly enables volatile.  This
is useful if you want to use a different locking system or write your own.  Pass
any true value to enable.  This is an optional parameter, and defaults to 0 (disabled).

=item * debug

Currently, I<debug> mode does nothing more than print all errors to STDERR.
However, it may be expanded in the future to log more debugging information.
Pass any true value to enable.  This is an optional paramter, and defaults to 0
(disabled).

=back

=head1 TIE INTERFACE

With DBM::Deep you can access your databases using Perl's standard hash/array
syntax.  Because all Deep objects are I<tied> to hashes or arrays, you can treat
them as such.  Deep will intercept all reads/writes and direct them to the right
place -- the DB file.  This has nothing to do with the L<TIE CONSTRUCTION> section
above.  This simply tells you how to use DBM::Deep using regular hashes and arrays, 
rather than calling functions like get() and put() (although those work too).
It is entirely up to you how to want to access your databases.

=head2 HASHES

You can treat any DBM::Deep object like a normal Perl hash.  Add keys, or even
nested hashes (or arrays) using standard Perl syntax:

	my $db = new DBM::Deep "foo.db";
	
	$db->{mykey} = "myvalue";
	$db->{myhash} = {};
	$db->{myhash}->{subkey} = "subvalue";

	print $db->{myhash}->{subkey} . "\n";

You can even step through hash keys using the normal Perl C<keys()> function:

	foreach my $key (keys %$db) {
		print "$key: " . $db->{$key} . "\n";
	}

Remember that Perl's C<keys()> function extracts I<every> key from the hash and
pushes them onto an array, all before the loop even begins.  If you have an extra 
large hash, this may exhaust Perl's memory.  Instead, consider using Perl's 
C<each()> function, which pulls keys/values one at a time, using very little memory:

	while (my ($key, $value) = each %$db) {
		print "$key: $value\n";
	}

=head2 ARRAYS

As with hashes, you can treat any DBM::Deep object like a normal Perl array.  This
includes C<length()>, C<push()>, C<pop()>, C<shift()>, C<unshift()> and C<splice()>.
The object must have first been created using type C<DBM::Deep::TYPE_ARRAY>, or
simply be a child array reference.  Examples:

	my $db = new DBM::Deep "foo.db"; # hash
	$db->{myarray} = []; # new array ref inside hash
	
	$db->{myarray}->[0] = "foo";
	push @{$db->{myarray}}, "bar", "baz";
	unshift @{$db->{myarray}}, "bah";
	
	my $last_elem = pop @{$db->{myarray}}; # baz
	my $first_elem = shift @{$db->{myarray}}; # bah
	my $second_elem = $db->{myarray}->[1]; # bar

=head1 OO INTERFACE

In addition to the I<tie()> interface, you can also use a standard OO interface
to manipulate all aspects of DBM::Deep databases.  Each type of object (hash or
array) has its own methods, but both types share the following methods: C<put()>, 
C<get()>, C<exists()>, C<delete()> and C<clear()>.

=over

=item * put()

Stores a new hash key/value pair, or sets an array element value.  Takes two
arguments, the hash key or array index, and the new value.  The value can be
a scalar, hash ref or array ref.  Returns true on success, false on failure.

	$db->put("foo", "bar");

=item * get()

Fetches the value of a hash key or array element.  Takes one argument: the hash
key or array index.  Returns a scalar, hash ref or array ref, depending on the 
data type stored.

	my $value = $db->get("foo");

=item * exists()

Checks if a hash key or array index exists.  Takes one argument: the hash key or
array index.  Returns true if it exists, false if not.

	if ($db->exists("foo")) { print "yay!\n"; }

=item * delete()

Deletes one hash key/value pair or array element.  Takes one argument: the hash
key or array index.  Returns true on success, false if not found.  For arrays,
the remaining elements located after the deleted element are NOT moved over.
The deleted element is essentially just undefined.  Please note that the space
occupied by the deleted key/value or element is B<not> reused again -- see 
L<UNUSED SPACE RECOVERY> below for details and workarounds.

	$db->delete("foo");

=item * clear()

Deletes B<all> hash keys or array elements.  Takes no arguments.  No return 
value.  Please note that the space occupied by the deleted keys/values or 
elements is B<not> reused again -- see L<UNUSED SPACE RECOVERY> below for 
details and workarounds.

	$db->clear();

=back

=head2 HASHES

For hashes, DBM::Deep supports all the common methods described above, and the 
following additional methods: C<first_key()> and C<next_key()>.

=over

=item * first_key()

Returns the "first" key in the hash.  As with built-in Perl hashes, keys are fetched
in an undefined order (which appears random).  Takes no arguments, returns the key
as a scalar value.

	my $key = $db->first_key();

=item * next_key()

Returns the "next" key in the hash, given the previous one as the sole argument.
Returns undef if there are no more keys to be fetched.

	$key = $db->next_key($key);

=back

Here are some examples of using hashes:

	my $db = new DBM::Deep "foo.db";
	
	$db->put("foo", "bar");
	print "foo: " . $db->get("foo") . "\n";
	
	$db->put("baz", {}); # new child hash ref
	$db->get("baz")->put("buz", "biz");
	print "buz: " . $db->get("baz")->get("buz") . "\n";
	
	my $key = $db->first_key();
	while ($key) {
		print "$key: " . $db->get($key) . "\n";
		$key = $db->next_key($key);	
	}
	
	if ($db->exists("foo")) { $db->delete("foo"); }

=head2 ARRAYS

For arrays, DBM::Deep supports all the common methods described above, and the 
following additional methods: C<length()>, C<push()>, C<pop()>, C<shift()>, 
C<unshift()> and C<splice()>.

=over

=item * length()

Returns the number of elements in the array.  Takes no arguments.

	my $len = $db->length();

=item * push()

Adds one or more elements onto the end of the array.  Accepts scalars, hash refs
or array refs.  No return value.

	$db->push("foo", "bar", {});

=item * pop()

Fetches the last element in the array, and deletes it.  Takes no arguments.
Returns undef if array is empty.  Returns the element value.

	my $elem = $db->pop();

=item * shift()

Fetches the first element in the array, deletes it, then shifts all the remaining
elements over to take up the space.  Returns the element value.  This method is
not recommended with large arrays -- see L<LARGE ARRAYS> below for details.

	my $elem = $db->shift();

=item * unshift()

Inserts one or more elements onto the beginning of the array, shifting all existing
elements over to make room.  Accepts scalars, hash refs or array refs.  No return
value.  This method is not recommended with large arrays -- see L<LARGE ARRAYS> 
below for details.

	$db->unshift("foo", "bar", {});

=item * splice()

Performs exactly like Perl's built-in function of the same name.  See L<perldoc -f 
splice> for usage -- it is too complicated to document here.  This method is
not recommended with large arrays -- see L<LARGE ARRAYS> below for details.

=back

Here are some examples of using arrays:

	my $db = new DBM::Deep(
		file => "foo.db",
		type => DBM::Deep::TYPE_ARRAY
	);
	
	$db->push("bar", "baz");
	$db->unshift("foo");
	$db->put(3, "buz");
	
	my $len = $db->length();
	print "length: $len\n"; # 4
	
	for (my $k=0; $k<$len; $k++) {
		print "$k: " . $db->get($k) . "\n";
	}
	
	$db->splice(1, 2, "biz", "baf");
	
	while (my $elem = shift @$db) {
		print "shifted: $elem\n";
	}

=head1 LOCKING

Enable automatic file locking by passing a true value to the C<locking> parameter
when constructing your DBM::Deep object (see L<SETUP> above).

	my $db = new DBM::Deep(
		file => "foo.db",
		locking => 1
	);

This causes Deep to C<flock()> the underlying FileHandle object with exclusive mode 
for writes, and shared mode for reads.  This is required if you have multiple 
processes accessing the same database file, to avoid file corruption.  Please note 
that C<flock()> does NOT work for files over NFS.  See L<DB OVER NFS> below for more.

=head2 EXPLICIT LOCKING

You can explicitly lock a database, so it remains locked for multiple transactions.
This is done by calling the C<lock()> method, and passing an optional lock mode
argument (defaults to exlusive mode).  This is particularly useful for things like
counters, where the current value needs to be fetched, incremented, then stored again.

	$db->lock();
	my $counter = $db->get("counter");
	$counter++;
	$db->put("counter", $counter);
	$db->unlock();

	# or...
	
	$db->lock();
	$db->{counter}++;
	$db->unlock();

You can pass C<lock()> an optional argument, which specifies which mode to use
(exclusive or shared).  Use one of these two constants: C<DBM::Deep::LOCK_EX> or
C<DBM::Deep::LOCK_SH>.  These are passed directly to C<flock()>, and are the same
as the constants defined in Perl's C<Fcntl> module.

	$db->lock( DBM::Deep::LOCK_SH );
	# something here
	$db->unlock();

If you want to implement your own file locking scheme, be sure to create your
DBM::Deep objects setting the C<volatile> option to true.  This hints to Deep
that the DB file may change between transactions.  See L<LOW-LEVEL ACCESS> 
below for more.

=head1 ERROR HANDLING

Most DBM::Deep methods return a true value for success, and a false value for
failure.  Upon failure, the actual error message is stored in an internal scalar, 
which can be fetched by calling the C<error()> method.

	my $db = new DBM::Deep "foo.db"; # hash
	$db->push("foo"); # ILLEGAL -- array only func
	
	print $db->error(); # prints error message

You can then call C<clear_error()> to clear the current error state.

	$db->clear_error();

It is always a good idea to check the error state upon object creation.  Deep
immediately tries to C<open()> the FileHandle, so if you don't have sufficient
permissions or some other filesystem error occurs, you should act accordingly
before trying to access the database.

	my $db = new DBM::Deep("foo.db");
	if ($db->error()) {
		die "ERROR: " . $db->error();
	}

If you set the C<debug> option to true when creating your DBM::Deep object,
all errors are printed to STDERR.

=head1 LARGEFILE SUPPORT

If you have a 64-bit system, and your Perl is compiled with both largefile
and 64-bit support, you I<may> be able to create databases larger than 2 GB.
DBM::Deep by default uses 32-bit file offset tags, but these can be changed
by calling the static C<set_pack()> method before you do anything else.

	DBM::Deep::set_pack(8, 'Q');

This tells DBM::Deep to pack all file offsets with 8-byte (64-bit) quad words 
instead of 32-bit longs.  After setting these values your DB files have a 
theoretical maximum size of 16 XB (exabytes).



B<Note:> Changing these values will B<NOT> work for existing database files.
Only change this for new files, and make sure it stays set throughout the
file's life.  If you set these values, you can no longer access 32-bit
DB files.  You can call C<set_pack(4, 'N')> to change back to 32-bit mode.



B<Note:> I have not personally tested files > 2 GB -- all my systems have 
only a 32-bit Perl.  If anyone tries this, please tell me what happens!

=head1 LOW-LEVEL ACCESS

If you require low-level access to the underlying FileHandle that Deep uses,
you can call the C<fh()> method, which returns the handle:

	my $fh = $db->fh();

This method can be called on the root level of the datbase, or any child
hashes or arrays.  All levels share a I<root> structure, which contains things
like the FileHandle, a reference counter, and all your options you specified
when you created the object.  You can get access to this root structure by 
calling the C<root()> method.

	my $root = $db->root();

This is useful for changing options after the object has already been created,
such as enabling/disabling locking, volatile or debug modes.  You can also
store your own temporary user data in this structure (be wary of name collision), 
which is then accessible from any child hash or array.

=head1 CAVEATS / ISSUES / BUGS

This section describes all the known issues with DBM::Deep.  It you have found
something that is not listed here, please send e-mail to L<jhuckaby@cpan.org>.

=head2 UNUSED SPACE RECOVERY

One major caveat with Deep is that space occupied by existing keys and
values is not recovered when they are deleted.  Meaning if you keep deleting
and adding new keys, your file will continuously grow.  I am working on this,
but in the meantime you can call the built-in C<optimize()> method from time to 
time (perhaps in a crontab or something) to rekindle all your unused space.

	$db->optimize(); # returns true on success

This rebuilds the ENTIRE database into a new file, then moves it on top of
the original.  The new file will have no unused space, thus it will take up as
little disk space as possible.  Please note that this operation can take 
a long time for large files, and you need enough disk space to hold 2 copies
of your DB file.  The temporary file is created in the same directory as the 
original, named with ".tmp", and is deleted when the operation completes.
Oh, and if locking is enabled, the DB is automatically locked for the entire
duration of the copy.



B<WARNING:> Only call optimize() on the top-level node of the database, and make
sure there are no child references lying around.  Deep keeps a reference counter, 
and if it is greater than 1, optimize() will abort and return undef.

=head2 AUTOVIVIFICATION

Unfortunately, autovivification doesn't always work.  This appears to be a bug
in Perl's tie() system, as I<Jakob Schmidt> encountered the very same issue with
his I<DWH_FIle> module (see L<cpan.org>).  Basically, your milage may vary when 
issuing statements like this:

	$db->{a} = { b => [ 1, 2, { c => [ 'd', { e => 'f' } ] } ] };

This causes 3 hashes and 2 arrays to be created in the database all in one
fell swoop, and all nested within each other.  Perl I<may> choke on this, and 
fail to create one or more of the nested structures.  This doesn't appear 
to be a bug in DBM::Deep, but I am still investigating it.  The problem is
intermittent.  For safety, I recommend creating nested structures using a 
series of commands instead of just one, which will always work:

	$db->{a} = {};
	$db->{a}->{b} = [];
	
	my $b = $db->{a}->{b};
	$b->[0] = 1;
	$b->[1] = 2;
	$b->[2] = {};
	$b->[2]->{c} = [];
	
	my $c = $b->[2]->{c};
	$c->[0] = 'd';
	$c->[1] = {};
	$c->[1]->{e} = 'f';
	
	undef $c;
	undef $b;

B<Note:> I have yet to recreate this bug with Perl 5.8.1.  Perhaps the issue
has been resolved?  Will update as events warrant.

=head2 FILE CORRUPTION

The current level of error handling in Deep is minimal.  Files I<are> checked
for a 32-bit signature on open(), but other corruption in files can cause
segmentation faults.  Deep may try to seek() past the end of a file, or get
stuck in an infinite loop depending on the level of corruption.  File write
operations are not checked for failure (for speed), so if you happen to run
out of disk space, Deep will probably fail in a bad way.  These things will 
be addressed in a later version of DBM::Deep.

=head2 DB OVER NFS

Beware of using DB files over NFS.  Deep uses flock(), which works well on local
filesystems, but will NOT protect you from file corruption over NFS.  I've heard 
about setting up your NFS server with a locking daemon, then using lockf() to 
lock your files, but your milage may vary there as well.  From what I understand, 
there is no real way to do it.  However, if you need access to the underlying 
FileHandle in Deep for using some other kind of locking scheme, see the 
L<LOW-LEVEL ACCESS> section above.

=head2 COPYING OBJECTS

Beware of copying tied objects in Perl.  Very bad things can happen.  Instead,
use Deep's C<clone()> method which safely copies the object and returns a new,
blessed, tied hash or array to the same level in the DB.

	my $copy = $db->clone();

=head2 LARGE ARRAYS

Beware of using C<shift()>, C<unshift()> or C<splice()> with large arrays.
These functions cause every element in the array to move, which can be murder
on DBM::Deep, as every element has to be fetched from disk, then stored again in
a different location.  This will be addressed in a later version.

=head1 AUTHOR

Joseph Huckaby, L<jhuckaby@cpan.org>

=head1 SEE ALSO

perltie, Tie::Hash, flock(2)

=head1 LICENSE

Copyright (c) 2002-2004 Joseph Huckaby.  All Rights Reserved.
This is free software, you may use it and distribute it under the
same terms as Perl itself.

=cut
