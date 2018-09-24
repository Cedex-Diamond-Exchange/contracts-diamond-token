    pragma solidity ^0.4.24;
    
    /*
    * @title String & slice utility library for Solidity contracts.
    * @author Nick Johnson <arachnid@notdot.net>
    *
    * @dev Functionality in this library is largely implemented using an
    *      abstraction called a 'slice'. A slice represents a part of a string -
    *      anything from the entire string to a single character, or even no
    *      an offset and a length, copying and manipulating slices is a lot less
    *      expensive than copying and manipulating the strings they reference.
    *
    *      To further reduce gas costs, most functions on slice that need to return
    *      a slice modify the original one instead of allocating a new one; for
    *      instance, `s.split(".")` will return the text up to the first '.',
    *      modifying s to only contain the remainder of the string after the '.'.
    *      In situations where you do not want to modify the original slice, you
    *      can make a copy first with `.copy()`, for example:
    *      `s.copy().split(".")`. Try and avoid using this idiom in loops; since
    *      Solidity has no memory management, it will result in allocating many
    *      short-lived slices that are later discarded.
    *
    *      Functions that return two slices come in two versions: a non-allocating
    *      version that takes the second slice as an argument, modifying it in
    *      place, and an allocating version that allocates and returns the second
    *      slice; see `nextRune` for example.
    *
    *      Functions that have to copy string data will return strings rather than
    *      slices; these can be cast back to slices for further processing if
    *      required.
    *
    *      For convenience, some functions are provided with non-modifying
    *      variants that create a new slice and return both; for instance,
    *      `s.splitNew('.')` leaves s unmodified, and returns two values
    *      corresponding to the left and right parts of the string.
    */
    
    library strings {
    struct slice {
      uint _len;
      uint _ptr;
    }
    
    function memcpy(uint dest, uint src, uint len) private pure {
      // Copy word-length chunks while possible
      for(; len >= 32; len -= 32) {
          assembly {
              mstore(dest, mload(src))
          }
          dest += 32;
          src += 32;
      }
    
      // Copy remaining bytes
      uint mask = 256 ** (32 - len) - 1;
      assembly {
          let srcpart := and(mload(src), not(mask))
          let destpart := and(mload(dest), mask)
          mstore(dest, or(destpart, srcpart))
      }
    }
    
    /*
    * @dev Returns a slice containing the entire string.
    * @param self The string to make a slice from.
    * @return A newly allocated slice containing the entire string.
    */
    function toSlice(string memory self) internal pure returns (slice memory) {
      uint ptr;
      assembly {
          ptr := add(self, 0x20)
      }
      return slice(bytes(self).length, ptr);
    }
    
    /*
    * @dev Returns the length of a null-terminated bytes32 string.
    * @param self The value to find the length of.
    * @return The length of the string, from 0 to 32.
    */
    function len(bytes32 self) internal pure returns (uint) {
      uint ret;
      if (self == 0)
          return 0;
      if (self & 0xffffffffffffffffffffffffffffffff == 0) {
          ret += 16;
          self = bytes32(uint(self) / 0x100000000000000000000000000000000);
      }
      if (self & 0xffffffffffffffff == 0) {
          ret += 8;
          self = bytes32(uint(self) / 0x10000000000000000);
      }
      if (self & 0xffffffff == 0) {
          ret += 4;
          self = bytes32(uint(self) / 0x100000000);
      }
      if (self & 0xffff == 0) {
          ret += 2;
          self = bytes32(uint(self) / 0x10000);
      }
      if (self & 0xff == 0) {
          ret += 1;
      }
      return 32 - ret;
    }
    
    /*
    * @dev Returns a slice containing the entire bytes32, interpreted as a
    *      null-terminated utf-8 string.
    * @param self The bytes32 value to convert to a slice.
    * @return A new slice containing the value of the input argument up to the
    *         first null.
    */
    function toSliceB32(bytes32 self) internal pure returns (slice memory ret) {
      // Allocate space for `self` in memory, copy it there, and point ret at it
        assembly {
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, 0x20))
            mstore(ptr, self)
            mstore(add(ret, 0x20), ptr)
        }
        ret._len = len(self);
    }
    
    /*
    * @dev Returns a new slice containing the same data as the current slice.
    * @param self The slice to copy.
    * @return A new slice containing the same data as `self`.
    */
    function copy(slice memory self) internal pure returns (slice memory) {
      return slice(self._len, self._ptr);
    }
    
    /*
    * @dev Copies a slice to a new string.
    * @param self The slice to copy.
    * @return A newly allocated string containing the slice's text.
    */
    function toString(slice memory self) internal pure returns (string memory) {
      string memory ret = new string(self._len);
      uint retptr;
      assembly { retptr := add(ret, 32) }
    
      memcpy(retptr, self._ptr, self._len);
      return ret;
    }
    
    /*
    * @dev Returns the length in runes of the slice. Note that this operation
    *      takes time proportional to the length of the slice; avoid using it
    *      in loops, and call `slice.empty()` if you only need to know whether
    *      the slice is empty or not.
    * @param self The slice to operate on.
    * @return The length of the slice in runes.
    */
    function len(slice memory self) internal pure returns (uint l) {
      // Starting at ptr-31 means the LSB will be the byte we care about
      uint ptr = self._ptr - 31;
      uint end = ptr + self._len;
      for (l = 0; ptr < end; l++) {
          uint8 b;
          assembly { b := and(mload(ptr), 0xFF) }
          if (b < 0x80) {
              ptr += 1;
          } else if(b < 0xE0) {
              ptr += 2;
          } else if(b < 0xF0) {
              ptr += 3;
          } else if(b < 0xF8) {
              ptr += 4;
          } else if(b < 0xFC) {
              ptr += 5;
          } else {
              ptr += 6;
          }
      }
    }
    
    /*
    * @dev Returns true if the slice is empty (has a length of 0).
    * @param self The slice to operate on.
    * @return True if the slice is empty, False otherwise.
    */
    function empty(slice memory self) internal pure returns (bool) {
      return self._len == 0;
    }
    
    /*
    * @dev Returns a positive number if `other` comes lexicographically after
    *      `self`, a negative number if it comes before, or zero if the
    *      contents of the two slices are equal. Comparison is done per-rune,
    *      on unicode codepoints.
    * @param self The first slice to compare.
    * @param other The second slice to compare.
    * @return The result of the comparison.
    */
    function compare(slice memory self, slice memory other) internal pure returns (int) {
      uint shortest = self._len;
      if (other._len < self._len)
          shortest = other._len;
    
      uint selfptr = self._ptr;
      uint otherptr = other._ptr;
      for (uint idx = 0; idx < shortest; idx += 32) {
          uint a;
          uint b;
          assembly {
              a := mload(selfptr)
              b := mload(otherptr)
          }
          if (a != b) {
              // Mask out irrelevant bytes and check again
              uint256 mask = uint256(-1); // 0xffff...
              if(shortest < 32) {
                mask = ~(2 ** (8 * (32 - shortest + idx)) - 1);
              }
              uint256 diff = (a & mask) - (b & mask);
              if (diff != 0)
                  return int(diff);
          }
          selfptr += 32;
          otherptr += 32;
      }
      return int(self._len) - int(other._len);
    }
    
    /*
    * @dev Returns true if the two slices contain the same text.
    * @param self The first slice to compare.
    * @param self The second slice to compare.
    * @return True if the slices are equal, false otherwise.
    */
    function equals(slice memory self, slice memory other) internal pure returns (bool) {
      return compare(self, other) == 0;
    }
    
    /*
    * @dev Extracts the first rune in the slice into `rune`, advancing the
    *      slice to point to the next rune and returning `self`.
    * @param self The slice to operate on.
    * @param rune The slice that will contain the first rune.
    * @return `rune`.
    */
    function nextRune(slice memory self, slice memory rune) internal pure returns (slice memory) {
      rune._ptr = self._ptr;
    
      if (self._len == 0) {
          rune._len = 0;
          return rune;
      }
    
      uint l;
      uint b;
      // Load the first byte of the rune into the LSBs of b
      assembly { b := and(mload(sub(mload(add(self, 32)), 31)), 0xFF) }
      if (b < 0x80) {
          l = 1;
      } else if(b < 0xE0) {
          l = 2;
      } else if(b < 0xF0) {
          l = 3;
      } else {
          l = 4;
      }
    
      // Check for truncated codepoints
      if (l > self._len) {
          rune._len = self._len;
          self._ptr += self._len;
          self._len = 0;
          return rune;
      }
    
      self._ptr += l;
      self._len -= l;
      rune._len = l;
      return rune;
    }
    
    /*
    * @dev Returns the first rune in the slice, advancing the slice to point
    *      to the next rune.
    * @param self The slice to operate on.
    * @return A slice containing only the first rune from `self`.
    */
    function nextRune(slice memory self) internal pure returns (slice memory ret) {
      nextRune(self, ret);
    }
    
    /*
    * @dev Returns the number of the first codepoint in the slice.
    * @param self The slice to operate on.
    * @return The number of the first codepoint in the slice.
    */
    function ord(slice memory self) internal pure returns (uint ret) {
      if (self._len == 0) {
          return 0;
      }
    
      uint word;
      uint length;
      uint divisor = 2 ** 248;
    
      // Load the rune into the MSBs of b
      assembly { word:= mload(mload(add(self, 32))) }
      uint b = word / divisor;
      if (b < 0x80) {
          ret = b;
          length = 1;
      } else if(b < 0xE0) {
          ret = b & 0x1F;
          length = 2;
      } else if(b < 0xF0) {
          ret = b & 0x0F;
          length = 3;
      } else {
          ret = b & 0x07;
          length = 4;
      }
    
      // Check for truncated codepoints
      if (length > self._len) {
          return 0;
      }
    
      for (uint i = 1; i < length; i++) {
          divisor = divisor / 256;
          b = (word / divisor) & 0xFF;
          if (b & 0xC0 != 0x80) {
              // Invalid UTF-8 sequence
              return 0;
          }
          ret = (ret * 64) | (b & 0x3F);
      }
    
      return ret;
    }
    
    /*
    * @dev Returns the keccak-256 hash of the slice.
    * @param self The slice to hash.
    * @return The hash of the slice.
    */
    function keccak(slice memory self) internal pure returns (bytes32 ret) {
      assembly {
          ret := keccak256(mload(add(self, 32)), mload(self))
      }
    }
    
    /*
    * @dev Returns true if `self` starts with `needle`.
    * @param self The slice to operate on.
    * @param needle The slice to search for.
    * @return True if the slice starts with the provided text, false otherwise.
    */
    function startsWith(slice memory self, slice memory needle) internal pure returns (bool) {
      if (self._len < needle._len) {
          return false;
      }
    
      if (self._ptr == needle._ptr) {
          return true;
      }
    
      bool equal;
      assembly {
          let length := mload(needle)
          let selfptr := mload(add(self, 0x20))
          let needleptr := mload(add(needle, 0x20))
          equal := eq(keccak256(selfptr, length), keccak256(needleptr, length))
      }
      return equal;
    }
    
    /*
    * @dev If `self` starts with `needle`, `needle` is removed from the
    *      beginning of `self`. Otherwise, `self` is unmodified.
    * @param self The slice to operate on.
    * @param needle The slice to search for.
    * @return `self`
    */
    function beyond(slice memory self, slice memory needle) internal pure returns (slice memory) {
      if (self._len < needle._len) {
          return self;
      }
    
      bool equal = true;
      if (self._ptr != needle._ptr) {
          assembly {
              let length := mload(needle)
              let selfptr := mload(add(self, 0x20))
              let needleptr := mload(add(needle, 0x20))
              equal := eq(keccak256(selfptr, length), keccak256(needleptr, length))
          }
      }
    
      if (equal) {
          self._len -= needle._len;
          self._ptr += needle._len;
      }
    
      return self;
    }
    
    /*
    * @dev Returns true if the slice ends with `needle`.
    * @param self The slice to operate on.
    * @param needle The slice to search for.
    * @return True if the slice starts with the provided text, false otherwise.
    */
    function endsWith(slice memory self, slice memory needle) internal pure returns (bool) {
      if (self._len < needle._len) {
          return false;
      }
    
      uint selfptr = self._ptr + self._len - needle._len;
    
      if (selfptr == needle._ptr) {
          return true;
      }
    
      bool equal;
      assembly {
          let length := mload(needle)
          let needleptr := mload(add(needle, 0x20))
          equal := eq(keccak256(selfptr, length), keccak256(needleptr, length))
      }
    
      return equal;
    }
    
    /*
    * @dev If `self` ends with `needle`, `needle` is removed from the
    *      end of `self`. Otherwise, `self` is unmodified.
    * @param self The slice to operate on.
    * @param needle The slice to search for.
    * @return `self`
    */
    function until(slice memory self, slice memory needle) internal pure returns (slice memory) {
      if (self._len < needle._len) {
          return self;
      }
    
      uint selfptr = self._ptr + self._len - needle._len;
      bool equal = true;
      if (selfptr != needle._ptr) {
          assembly {
              let length := mload(needle)
              let needleptr := mload(add(needle, 0x20))
              equal := eq(keccak256(selfptr, length), keccak256(needleptr, length))
          }
      }
    
      if (equal) {
          self._len -= needle._len;
      }
    
      return self;
    }
    
    // Returns the memory address of the first byte of the first occurrence of
    // `needle` in `self`, or the first byte after `self` if not found.
    function findPtr(uint selflen, uint selfptr, uint needlelen, uint needleptr) private pure returns (uint) {
      uint ptr = selfptr;
      uint idx;
    
      if (needlelen <= selflen) {
          if (needlelen <= 32) {
              bytes32 mask = bytes32(~(2 ** (8 * (32 - needlelen)) - 1));
    
              bytes32 needledata;
              assembly { needledata := and(mload(needleptr), mask) }
    
              uint end = selfptr + selflen - needlelen;
              bytes32 ptrdata;
              assembly { ptrdata := and(mload(ptr), mask) }
    
              while (ptrdata != needledata) {
                  if (ptr >= end)
                      return selfptr + selflen;
                  ptr++;
                  assembly { ptrdata := and(mload(ptr), mask) }
              }
              return ptr;
          } else {
              // For long needles, use hashing
              bytes32 hash;
              assembly { hash := keccak256(needleptr, needlelen) }
    
              for (idx = 0; idx <= selflen - needlelen; idx++) {
                  bytes32 testHash;
                  assembly { testHash := keccak256(ptr, needlelen) }
                  if (hash == testHash)
                      return ptr;
                  ptr += 1;
              }
          }
      }
      return selfptr + selflen;
    }
    
    // Returns the memory address of the first byte after the last occurrence of
    // `needle` in `self`, or the address of `self` if not found.
    function rfindPtr(uint selflen, uint selfptr, uint needlelen, uint needleptr) private pure returns (uint) {
      uint ptr;
    
      if (needlelen <= selflen) {
          if (needlelen <= 32) {
              bytes32 mask = bytes32(~(2 ** (8 * (32 - needlelen)) - 1));
    
              bytes32 needledata;
              assembly { needledata := and(mload(needleptr), mask) }
    
              ptr = selfptr + selflen - needlelen;
              bytes32 ptrdata;
              assembly { ptrdata := and(mload(ptr), mask) }
    
              while (ptrdata != needledata) {
                  if (ptr <= selfptr)
                      return selfptr;
                  ptr--;
                  assembly { ptrdata := and(mload(ptr), mask) }
              }
              return ptr + needlelen;
          } else {
              // For long needles, use hashing
              bytes32 hash;
              assembly { hash := keccak256(needleptr, needlelen) }
              ptr = selfptr + (selflen - needlelen);
              while (ptr >= selfptr) {
                  bytes32 testHash;
                  assembly { testHash := keccak256(ptr, needlelen) }
                  if (hash == testHash)
                      return ptr + needlelen;
                  ptr -= 1;
              }
          }
      }
      return selfptr;
    }
    
    /*
    * @dev Modifies `self` to contain everything from the first occurrence of
    *      `needle` to the end of the slice. `self` is set to the empty slice
    *      if `needle` is not found.
    * @param self The slice to search and modify.
    * @param needle The text to search for.
    * @return `self`.
    */
    function find(slice memory self, slice memory needle) internal pure returns (slice memory) {
      uint ptr = findPtr(self._len, self._ptr, needle._len, needle._ptr);
      self._len -= ptr - self._ptr;
      self._ptr = ptr;
      return self;
    }
    
    /*
    * @dev Modifies `self` to contain the part of the string from the start of
    *      `self` to the end of the first occurrence of `needle`. If `needle`
    *      is not found, `self` is set to the empty slice.
    * @param self The slice to search and modify.
    * @param needle The text to search for.
    * @return `self`.
    */
    function rfind(slice memory self, slice memory needle) internal pure returns (slice memory) {
      uint ptr = rfindPtr(self._len, self._ptr, needle._len, needle._ptr);
      self._len = ptr - self._ptr;
      return self;
    }
    
    /*
    * @dev Splits the slice, setting `self` to everything after the first
    *      occurrence of `needle`, and `token` to everything before it. If
    *      `needle` does not occur in `self`, `self` is set to the empty slice,
    *      and `token` is set to the entirety of `self`.
    * @param self The slice to split.
    * @param needle The text to search for in `self`.
    * @param token An output parameter to which the first token is written.
    * @return `token`.
    */
    function split(slice memory self, slice memory needle, slice memory token) internal pure returns (slice memory) {
      uint ptr = findPtr(self._len, self._ptr, needle._len, needle._ptr);
      token._ptr = self._ptr;
      token._len = ptr - self._ptr;
      if (ptr == self._ptr + self._len) {
          // Not found
          self._len = 0;
      } else {
          self._len -= token._len + needle._len;
          self._ptr = ptr + needle._len;
      }
      return token;
    }
    
    /*
    * @dev Splits the slice, setting `self` to everything after the first
    *      occurrence of `needle`, and returning everything before it. If
    *      `needle` does not occur in `self`, `self` is set to the empty slice,
    *      and the entirety of `self` is returned.
    * @param self The slice to split.
    * @param needle The text to search for in `self`.
    * @return The part of `self` up to the first occurrence of `delim`.
    */
    function split(slice memory self, slice memory needle) internal pure returns (slice memory token) {
      split(self, needle, token);
    }
    
    /*
    * @dev Splits the slice, setting `self` to everything before the last
    *      occurrence of `needle`, and `token` to everything after it. If
    *      `needle` does not occur in `self`, `self` is set to the empty slice,
    *      and `token` is set to the entirety of `self`.
    * @param self The slice to split.
    * @param needle The text to search for in `self`.
    * @param token An output parameter to which the first token is written.
    * @return `token`.
    */
    function rsplit(slice memory self, slice memory needle, slice memory token) internal pure returns (slice memory) {
      uint ptr = rfindPtr(self._len, self._ptr, needle._len, needle._ptr);
      token._ptr = ptr;
      token._len = self._len - (ptr - self._ptr);
      if (ptr == self._ptr) {
          // Not found
          self._len = 0;
      } else {
          self._len -= token._len + needle._len;
      }
      return token;
    }
    
    /*
    * @dev Splits the slice, setting `self` to everything before the last
    *      occurrence of `needle`, and returning everything after it. If
    *      `needle` does not occur in `self`, `self` is set to the empty slice,
    *      and the entirety of `self` is returned.
    * @param self The slice to split.
    * @param needle The text to search for in `self`.
    * @return The part of `self` after the last occurrence of `delim`.
    */
    function rsplit(slice memory self, slice memory needle) internal pure returns (slice memory token) {
      rsplit(self, needle, token);
    }
    
    /*
    * @dev Counts the number of nonoverlapping occurrences of `needle` in `self`.
    * @param self The slice to search.
    * @param needle The text to search for in `self`.
    * @return The number of occurrences of `needle` found in `self`.
    */
    function count(slice memory self, slice memory needle) internal pure returns (uint cnt) {
      uint ptr = findPtr(self._len, self._ptr, needle._len, needle._ptr) + needle._len;
      while (ptr <= self._ptr + self._len) {
          cnt++;
          ptr = findPtr(self._len - (ptr - self._ptr), ptr, needle._len, needle._ptr) + needle._len;
      }
    }
    
    /*
    * @dev Returns True if `self` contains `needle`.
    * @param self The slice to search.
    * @param needle The text to search for in `self`.
    * @return True if `needle` is found in `self`, false otherwise.
    */
    function contains(slice memory self, slice memory needle) internal pure returns (bool) {
      return rfindPtr(self._len, self._ptr, needle._len, needle._ptr) != self._ptr;
    }
    
    /*
    * @dev Returns a newly allocated string containing the concatenation of
    *      `self` and `other`.
    * @param self The first slice to concatenate.
    * @param other The second slice to concatenate.
    * @return The concatenation of the two strings.
    */
    function concat(slice memory self, slice memory other) internal pure returns (string memory) {
      string memory ret = new string(self._len + other._len);
      uint retptr;
      assembly { retptr := add(ret, 32) }
      memcpy(retptr, self._ptr, self._len);
      memcpy(retptr + self._len, other._ptr, other._len);
      return ret;
    }
    
    /*
    * @dev Joins an array of slices, using `self` as a delimiter, returning a
    *      newly allocated string.
    * @param self The delimiter to use.
    * @param parts A list of slices to join.
    * @return A newly allocated string containing all the slices in `parts`,
    *         joined with `self`.
    */
    function join(slice memory self, slice[] memory parts) internal pure returns (string memory) {
      if (parts.length == 0)
          return "";
    
      uint length = self._len * (parts.length - 1);
      for(uint i = 0; i < parts.length; i++)
          length += parts[i]._len;
    
      string memory ret = new string(length);
      uint retptr;
      assembly { retptr := add(ret, 32) }
    
      for(i = 0; i < parts.length; i++) {
          memcpy(retptr, parts[i]._ptr, parts[i]._len);
          retptr += parts[i]._len;
          if (i < parts.length - 1) {
              memcpy(retptr, self._ptr, self._len);
              retptr += self._len;
          }
      }
    
      return ret;
    }
    
    function uint2str(uint self) internal pure returns (string){
        if (self == 0) return "0";
        uint j = self;
        uint len;
        while (j != 0){
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (self != 0){
            bstr[k--] = byte(48 + self % 10);
            self /= 10;
        }
        return string(bstr);
    }
    
    function addressToAsciiString(address self) internal pure returns (string) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            byte b = byte(uint8(uint(self) / (2 ** (8 * (19 - i)))));
            byte hi = byte(uint8(b) / 16);
            byte lo = byte(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return concat(toSlice("0x"), toSlice(string(s)));
    } 
    
      function char(byte b) internal pure returns (byte c) {
        if (b < 10) return byte(uint8(b) + 0x30);
        else return byte(uint8(b) + 0x57);
    }
    }
    
    /**
    * @title SafeMath
    * @dev Math operations with safety checks that throw on error
    */
    library SafeMath {
    
    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
      if (a == 0) {
        return 0;
      }
      uint256 c = a * b;
      assert(c / a == b);
      return c;
    }
    
    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
      // assert(b > 0); // Solidity automatically throws when dividing by 0
      uint256 c = a / b;
      // assert(a == b * c + a % b); // There is no case in which this doesn't hold
      return c;
    }
    
    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      assert(b <= a);
      return a - b;
    }
    
    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 c = a + b;
      assert(c >= a);
      return c;
    }
    }
    
    
    /// @title Interface for contracts conforming to ERC-721: Non-Fungible Tokens
    /// @author Dieter Shirley <dete@axiomzen.co> (https://github.com/dete)
    contract ERC721 {
    function totalSupply() external view returns (uint256 total);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function ownerOf(string _diamondId) public view returns (address owner);
    function approve(address _to, string _diamondId) external;
    function transfer(address _to, string _diamondId) external;
    function transferFrom(address _from, address _to, string _diamondId) external;
    
    // Events
    event Transfer(address from, address to, string diamondId);
    event Approval(address owner, address approved, string diamondId);
    }
    
    contract DiamondAccessControl {
    
    address public CEO;
    
    mapping (address => bool) public admins;
    
    bool public paused = false;
    
    modifier onlyCEO() {
      require(msg.sender == CEO);
      _;
    }
    
    modifier onlyAdmin() {
      require(admins[msg.sender]);
      _;
    }
    
    /*** Pausable functionality adapted from OpenZeppelin ***/
    
    /// @dev Modifier to allow actions only when the contract IS NOT paused
    modifier whenNotPaused() {
      require(!paused);
      _;
    }
    
    modifier onlyAdminOrCEO() {
      require(admins[msg.sender] || msg.sender == CEO);
      _;
    }
    
    /// @dev Modifier to allow actions only when the contract IS paused
    modifier whenPaused {
      require(paused);
      _;
    }
    
    function setCEO(address _newCEO) external onlyCEO {
      require(_newCEO != address(0));
      CEO = _newCEO;
    }
    
    function setAdmin(address _newAdmin, bool isAdmin) external onlyCEO {
      require(_newAdmin != address(0));
      admins[_newAdmin] = isAdmin;
    }
    
    /// @dev Called by any "C-level" role to pause the contract. Used only when
    ///  a bug or exploit is detected and we need to limit damage.
    function pause() external onlyAdminOrCEO whenNotPaused {
      paused = true;
    }
    
    /// @dev Unpauses the smart contract. Can only be called by the CEO, since
    ///  one reason we may pause the contract is when admin account are
    ///  compromised.
    /// @notice This is public rather than external so it can be called by
    ///  derived contracts.
    function unpause() external onlyCEO whenPaused {
      // can't unpause if contract was upgraded
      paused = false;
    }
    }
    
/// @title Base contract for CryptoKitties. Holds all common structs, events and base variables.
/// @author Axiom Zen (https://www.axiomzen.co)
/// @dev See the KittyCore contract documentation to understand how the various contract facets are arranged.
contract DiamondBase is DiamondAccessControl {
    
    using SafeMath for uint256;
    using strings for *;
    
    event Transfer(address from, address to, string diamondId);
    event TransactionHistory(  
      string indexed _diamondId, 
      address _seller, 
      string _sellerId, 
      address _buyer, 
      string _buyerId, 
      uint256 _usdPrice, 
      uint256 _cedexPrice,
      uint256 timestamp
    );
    
    /*** DATA TYPE ***/
    /// @dev The main Kitty struct. Every dimond is represented by a copy of this structure
    struct Diamond {
      string ownerId;
      string status;
      string gemCompositeScore;
      string gemSubcategory;
      string certificateURL;
      string IPFS;
      string custodianName;
      string custodianLocation;
      string photoURL;
      string invoiceURL;
      uint256 creationTime;
      uint256 arrivalTime;
      uint256 confirmationTime;
      string additionalInfo;
    }
    
    // variable to store total amount of diamonds
    uint256 internal total;
    
    // Mapping for checking the existence of token with such diamond ID
    mapping(string => bool) internal diamondExists;
    
    // Mapping from adress to number of diamonds owned by this address
    mapping(address => uint) internal balances;
    
    // Mapping from diamond ID to owner address
    mapping (string => address) internal diamondIdToOwner;
    
    // Mapping from diamond ID to metadata
    mapping(string => Diamond) internal diamondIdToMetadata;
    
    // Mapping from diamond ID to an address that has been approved to call transferFrom()
    mapping(string => address) internal diamondIdToApproved;
    
    //Status Constants
    string constant STATUS_PENDING = "Pending";
    string constant STATUS_VERIFIED = "Verified";
    string constant STATUS_OUTSIDE  = "Outside";


    
    function _createDiamond(
      string _diamondId, 
      address _owner, 
      string _ownerId, 
      string _gemCompositeScore, 
      string _gemSubcategory, 
      string _certificateURL, 
      string _IPFS
    )  
      internal 
    {
      Diamond memory diamond;
      
      diamond.creationTime = now;
      diamond.status = "Pending";
      diamond.ownerId = _ownerId;
      diamond.gemCompositeScore = _gemCompositeScore;
      diamond.gemSubcategory = _gemSubcategory;
      diamond.certificateURL= _certificateURL;
      diamond.IPFS = _IPFS;
      
      diamondIdToMetadata[_diamondId] = diamond;
    
      _transfer(address(0), _owner, _diamondId);
      total = total.add(1);
      diamondExists[_diamondId] = true; 
    }
    
    function _transferInternal(
      string _diamondId, 
      address _seller, 
      string _sellerId, 
      address _buyer, 
      string _buyerId, 
      uint256 _usdPrice, 
      uint256 _cedexPrice
    )   
      internal 
    {
      Diamond storage diamond = diamondIdToMetadata[_diamondId];
      diamond.ownerId = _buyerId;
      _transfer(_seller, _buyer, _diamondId);   
      emit TransactionHistory(_diamondId, _seller, _sellerId, _buyer, _buyerId, _usdPrice, _cedexPrice, now);
    
    }
    
    function _transfer(address _from, address _to, string _diamondId) internal {
      if (_from != address(0)) {
          balances[_from] = balances[_from].sub(1);
      }
      balances[_to] = balances[_to].add(1);
      diamondIdToOwner[_diamondId] = _to;
      delete diamondIdToApproved[_diamondId];
      emit Transfer(_from, _to, _diamondId);
    }
    
    function _burn(string _diamondId) internal {
      address _from = diamondIdToOwner[_diamondId];
      balances[_from] = balances[_from].sub(1);
      total = total.sub(1);
      delete diamondIdToOwner[_diamondId];
      delete diamondIdToMetadata[_diamondId];
      delete diamondExists[_diamondId];
      delete diamondIdToApproved[_diamondId];
      emit Transfer(_from, address(0), _diamondId);
    }
    
    function _isDiamondOutside(string _diamondId) internal view returns (bool) {
      require(diamondExists[_diamondId]);
      return diamondIdToMetadata[_diamondId].status.toSlice().equals(STATUS_OUTSIDE.toSlice());
    }
    
    function _isDiamondVerified(string _diamondId) internal view returns (bool) {
      require(diamondExists[_diamondId]);
      return diamondIdToMetadata[_diamondId].status.toSlice().equals(STATUS_VERIFIED.toSlice());
    }
    
    function convertToSlice(string memory value) internal pure returns (strings.slice memory part) {
      string memory quote = "'";
      part = quote.toSlice().concat(value.toSlice()).toSlice().concat(quote.toSlice()).toSlice();
    }
}
    
    /// @title The ontract that manages ownership, ERC-721 (draft) compliant.
    contract DiamondBase721 is DiamondBase, ERC721 {
    
    function totalSupply() external view returns (uint256) {
      return total;
    }
    
    /**
    * @dev Gets the balance of the specified address
    * @param _owner address to query the balance of
    * @return uint256 representing the amount owned by the passed address
    */
    function balanceOf(address _owner) external view returns (uint256) {
      return balances[_owner];
    
    }
    
    /**
    * @dev Gets the owner of the specified diamond ID
    * @param _diamondId string ID of the diamond to query the owner of
    * @return owner address currently marked as the owner of the given diamond ID
    */
    function ownerOf(string _diamondId) public view returns (address) {
      require(diamondExists[_diamondId]);
      return diamondIdToOwner[_diamondId];
    }
    
    function approve(address _to, string _diamondId) external whenNotPaused {
      require(_isDiamondOutside(_diamondId));
      require(msg.sender == ownerOf(_diamondId));
      diamondIdToApproved[_diamondId] = _to;
      emit Approval(msg.sender, _to, _diamondId);
    }
    
    /**
    * @dev Transfers the ownership of a given diamond ID to another address
    * @param _to address to receive the ownership of the given diamond ID
    * @param _diamondId uint256 ID of the diamond to be transferred
    */
    function transfer(address _to, string _diamondId) external whenNotPaused {
      require(_isDiamondOutside(_diamondId));
      require(msg.sender == ownerOf(_diamondId));
      require(_to != address(0));
      require(_to != address(this));
      require(_to != ownerOf(_diamondId));
      _transfer(msg.sender, _to, _diamondId);
    }
    
    function transferFrom(address _from, address _to,  string _diamondId)
      external 
      whenNotPaused 
    {
      require(_isDiamondOutside(_diamondId));
      require(_from == ownerOf(_diamondId));
      require(_to != address(0));
      require(_to != address(this));
      require(_to != ownerOf(_diamondId));
      require(diamondIdToApproved[_diamondId] == msg.sender);
      _transfer(_from, _to, _diamondId);
    }
    
}
    
/// @dev The main contract, keeps track of diamonds.
contract DiamondCore is DiamondBase721 {
    using strings for *;
    
    /// @notice Creates the main Diamond smart contract instance.
    constructor() public {
      // the creator of the contract is the initial CEO
      CEO = msg.sender;
    }
    
    function createDiamond(
      string _diamondId, 
      address _owner, 
      string _ownerId, 
      string _gemCompositeScore, 
      string _gemSubcategory, 
      string _certificateURL, 
      string _IPFS
    ) 
      external 
      onlyAdminOrCEO 
      whenNotPaused 
    {
      require(!diamondExists[_diamondId]);
      require(_owner != address(0));
      require(_owner != address(this));
      _createDiamond( 
          _diamondId, 
          _owner, 
          _ownerId, 
          _gemCompositeScore, 
          _gemSubcategory, 
          _certificateURL, 
          _IPFS
      );
    }
    
    function updateDiamond(
      string _diamondId, 
      string _custodianName, 
      string _custodianLocation, 
      string _photoURL, 
      string _invoiceURL, 
      uint256 _arrivalTime, 
      uint256 _confirmationTime, 
      string _additionalInfo
    ) 
      external 
      onlyAdminOrCEO 
      whenNotPaused 
    {
      require(!_isDiamondOutside(_diamondId));
      
      Diamond storage diamond = diamondIdToMetadata[_diamondId];
      
      diamond.status = "Verified";
      diamond.custodianName = _custodianName;
      diamond.custodianLocation = _custodianLocation;
      diamond.photoURL = _photoURL;
      diamond.invoiceURL = _invoiceURL;
      diamond.arrivalTime = _arrivalTime;
      diamond.confirmationTime = _confirmationTime;
      diamond.additionalInfo = _additionalInfo;
    }
    
    function transferInternal(
      string _diamondId, 
      address _seller, 
      string _sellerId, 
      address _buyer, 
      string _buyerId, 
      uint256 _usdPrice, 
      uint256 _cedexPrice
    ) 
      external 
      onlyAdminOrCEO 
      whenNotPaused 
    {
      require(_isDiamondVerified(_diamondId));
      require(_seller == ownerOf(_diamondId));
      require(_buyer != address(0));
      require(_buyer != address(this));
      require(_buyer != ownerOf(_diamondId));
      _transferInternal(_diamondId, _seller, _sellerId, _buyer, _buyerId, _usdPrice, _cedexPrice);
    }
    
    function burn(string _diamondId) external onlyAdminOrCEO whenNotPaused {
      require(!_isDiamondOutside(_diamondId));
      _burn(_diamondId);
    }
    
    function withdraw() external {
      // TBD
    }
    
    function reinstate() external {
      // TBD
    }
    
    function getDiamond(string _diamondId) 
        external
        view
        returns(string diamondMetadata)
    {
        Diamond storage diamond = diamondIdToMetadata[_diamondId];
        
        strings.slice[] memory parts = new strings.slice[](15);
    
        parts[0] = convertToSlice(diamondIdToOwner[_diamondId].addressToAsciiString());
        parts[1] = convertToSlice(diamond.ownerId);
        parts[2] = convertToSlice(diamond.status);
        parts[3] = convertToSlice(diamond.gemCompositeScore);
        parts[4] = convertToSlice(diamond.gemSubcategory);
        parts[5] = convertToSlice(diamond.certificateURL);
        parts[6] = convertToSlice(diamond.IPFS);
        parts[7] = convertToSlice(diamond.custodianName);
        parts[8] = convertToSlice(diamond.custodianLocation);
        parts[9] = convertToSlice(diamond.photoURL);
        parts[10] = convertToSlice(diamond.invoiceURL);
        parts[11] = convertToSlice(diamond.additionalInfo);
        parts[12] = convertToSlice(diamond.creationTime.uint2str());
        parts[13] = convertToSlice(diamond.arrivalTime.uint2str());
        parts[14] = convertToSlice(diamond.confirmationTime.uint2str());

                
        diamondMetadata = ", ".toSlice().join(parts);
    }
}