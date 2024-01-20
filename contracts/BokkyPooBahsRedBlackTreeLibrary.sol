//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// ----------------------------------------------------------------------------
// BokkyPooBah's Red-Black Tree Library v1.0-pre-release-a
//
// A Solidity Red-Black Tree binary search library to store and access a sorted
// list of unsigned integer data. The Red-Black algorithm rebalances the binary
// search tree, resulting in O(log n) insert, remove and search time (and ~gas)
//
// https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary
//
//
// Enjoy. (c) BokkyPooBah / Bok Consulting Pty Ltd 2020. The MIT Licence.
// ----------------------------------------------------------------------------
library BokkyPooBahsRedBlackTreeLibrary {
  uint72 private constant EMPTY = 0;

  uint8 constant RED_FLAG_BIT = uint8(7);
  uint8 constant RED_FLAG_MASK = uint8(1 << RED_FLAG_BIT);
  uint8 constant NUM_IN_SEGMENT_MASK = uint8((1 << RED_FLAG_BIT) - 1);

  struct Tree {
    uint72 root;
    mapping(uint72 => Node) nodes;
  }

  struct Node {
    uint72 parent;
    uint72 left;
    uint72 right;
    uint32 tombstoneOffset; // Number of deleted segments, for gas efficiency
    uint8 data; // 1st bit "red", 2nd-8th bits "numInSegmentDeleted"
  }

  function setIsRed(Node storage node, bool red) internal {
    if (red) {
      node.data |= RED_FLAG_MASK; // Set the red flag bit to 1
    } else {
      node.data &= ~RED_FLAG_MASK; // Set the red flag bit to 0
    }
  }

  function isRed(Node storage node) internal view returns (bool) {
    return (node.data & RED_FLAG_MASK) != 0;
  }

  function setNumInSegmentDeleted(Node storage node, uint8 num) internal {
    require(num <= NUM_IN_SEGMENT_MASK, "Num exceeds 7 bits limit");
    node.data &= RED_FLAG_MASK; // Clear the 7 bits for num
    node.data |= num; // Set the 7 bits with the new value of num
  }

  function getNumInSegmentDeleted(Node storage node) internal view returns (uint8) {
    return node.data & NUM_IN_SEGMENT_MASK;
  }

  function createNodeData(bool red, uint8 numInSegmentDeleted) internal pure returns (uint8) {
    if (red) {
      return 0x80 | numInSegmentDeleted;
    } else {
      return numInSegmentDeleted;
    }
  }

  function first(Tree storage self) internal view returns (uint72 _key) {
    _key = self.root;
    if (_key != EMPTY) {
      while (self.nodes[_key].left != EMPTY) {
        _key = self.nodes[_key].left;
      }
    }
  }

  function last(Tree storage self) internal view returns (uint72 _key) {
    _key = self.root;
    if (_key != EMPTY) {
      while (self.nodes[_key].right != EMPTY) {
        _key = self.nodes[_key].right;
      }
    }
  }

  function next(Tree storage self, uint72 target) internal view returns (uint72 cursor) {
    require(target != EMPTY);
    if (self.nodes[target].right != EMPTY) {
      cursor = treeMinimum(self, self.nodes[target].right);
    } else {
      cursor = self.nodes[target].parent;
      while (cursor != EMPTY && target == self.nodes[cursor].right) {
        target = cursor;
        cursor = self.nodes[cursor].parent;
      }
    }
  }

  function prev(Tree storage self, uint72 target) internal view returns (uint72 cursor) {
    require(target != EMPTY);
    if (self.nodes[target].left != EMPTY) {
      cursor = treeMaximum(self, self.nodes[target].left);
    } else {
      cursor = self.nodes[target].parent;
      while (cursor != EMPTY && target == self.nodes[cursor].left) {
        target = cursor;
        cursor = self.nodes[cursor].parent;
      }
    }
  }

  function exists(Tree storage self, uint72 key) internal view returns (bool) {
    return (key != EMPTY) && ((key == self.root) || (self.nodes[key].parent != EMPTY));
  }

  function isEmpty(uint72 key) internal pure returns (bool) {
    return key == EMPTY;
  }

  function getEmpty() internal pure returns (uint) {
    return EMPTY;
  }

  function getNode(Tree storage self, uint72 key) internal view returns (Node storage node) {
    require(exists(self, key));
    return self.nodes[key];
  }

  function edit(Tree storage self, uint72 key, uint32 extraTombstoneOffset, uint8 numInSegmentDeleted) internal {
    require(exists(self, key));
    self.nodes[key].tombstoneOffset += extraTombstoneOffset;
    setNumInSegmentDeleted(self.nodes[key], numInSegmentDeleted);
  }

  function insert(Tree storage self, uint72 key) internal {
    require(key != EMPTY);
    require(!exists(self, key));
    uint72 cursor = EMPTY;
    uint72 probe = self.root;
    while (probe != EMPTY) {
      cursor = probe;
      if (key < probe) {
        probe = self.nodes[probe].left;
      } else {
        probe = self.nodes[probe].right;
      }
    }
    self.nodes[key] = Node({
      parent: cursor,
      left: EMPTY,
      right: EMPTY,
      tombstoneOffset: self.nodes[key].tombstoneOffset,
      data: createNodeData(true, getNumInSegmentDeleted(self.nodes[key]))
    });
    if (cursor == EMPTY) {
      self.root = key;
    } else if (key < cursor) {
      self.nodes[cursor].left = key;
    } else {
      self.nodes[cursor].right = key;
    }
    insertFixup(self, key);
  }

  function remove(Tree storage self, uint72 key) internal {
    require(key != EMPTY);
    require(exists(self, key));
    uint72 probe;
    uint72 cursor;
    if (self.nodes[key].left == EMPTY || self.nodes[key].right == EMPTY) {
      cursor = key;
    } else {
      cursor = self.nodes[key].right;
      while (self.nodes[cursor].left != EMPTY) {
        cursor = self.nodes[cursor].left;
      }
    }
    if (self.nodes[cursor].left != EMPTY) {
      probe = self.nodes[cursor].left;
    } else {
      probe = self.nodes[cursor].right;
    }
    uint72 yParent = self.nodes[cursor].parent;
    self.nodes[probe].parent = yParent;
    if (yParent != EMPTY) {
      if (cursor == self.nodes[yParent].left) {
        self.nodes[yParent].left = probe;
      } else {
        self.nodes[yParent].right = probe;
      }
    } else {
      self.root = probe;
    }
    bool doFixup = !isRed(self.nodes[cursor]);
    if (cursor != key) {
      replaceParent(self, cursor, key);
      self.nodes[cursor].left = self.nodes[key].left;
      self.nodes[self.nodes[cursor].left].parent = cursor;
      self.nodes[cursor].right = self.nodes[key].right;
      self.nodes[self.nodes[cursor].right].parent = cursor;
      setIsRed(self.nodes[cursor], isRed(self.nodes[key]));
      (cursor, key) = (key, cursor);
    }
    if (doFixup) {
      removeFixup(self, probe);
    }
    // Don't delete the node, so that we can re-use the tombstone offset if readding this price
    self.nodes[cursor].parent = EMPTY;
  }

  function treeMinimum(Tree storage self, uint72 key) private view returns (uint72) {
    while (self.nodes[key].left != EMPTY) {
      key = self.nodes[key].left;
    }
    return key;
  }

  function treeMaximum(Tree storage self, uint72 key) private view returns (uint72) {
    while (self.nodes[key].right != EMPTY) {
      key = self.nodes[key].right;
    }
    return key;
  }

  function rotateLeft(Tree storage self, uint72 key) private {
    uint72 cursor = self.nodes[key].right;
    uint72 keyParent = self.nodes[key].parent;
    uint72 cursorLeft = self.nodes[cursor].left;
    self.nodes[key].right = cursorLeft;
    if (cursorLeft != EMPTY) {
      self.nodes[cursorLeft].parent = key;
    }
    self.nodes[cursor].parent = keyParent;
    if (keyParent == EMPTY) {
      self.root = cursor;
    } else if (key == self.nodes[keyParent].left) {
      self.nodes[keyParent].left = cursor;
    } else {
      self.nodes[keyParent].right = cursor;
    }
    self.nodes[cursor].left = key;
    self.nodes[key].parent = cursor;
  }

  function rotateRight(Tree storage self, uint72 key) private {
    uint72 cursor = self.nodes[key].left;
    uint72 keyParent = self.nodes[key].parent;
    uint72 cursorRight = self.nodes[cursor].right;
    self.nodes[key].left = cursorRight;
    if (cursorRight != EMPTY) {
      self.nodes[cursorRight].parent = key;
    }
    self.nodes[cursor].parent = keyParent;
    if (keyParent == EMPTY) {
      self.root = cursor;
    } else if (key == self.nodes[keyParent].right) {
      self.nodes[keyParent].right = cursor;
    } else {
      self.nodes[keyParent].left = cursor;
    }
    self.nodes[cursor].right = key;
    self.nodes[key].parent = cursor;
  }

  function insertFixup(Tree storage self, uint72 key) private {
    uint72 cursor;
    while (key != self.root && isRed(self.nodes[self.nodes[key].parent])) {
      uint72 keyParent = self.nodes[key].parent;
      if (keyParent == self.nodes[self.nodes[keyParent].parent].left) {
        cursor = self.nodes[self.nodes[keyParent].parent].right;
        if (isRed(self.nodes[cursor])) {
          setIsRed(self.nodes[keyParent], false);
          setIsRed(self.nodes[cursor], false);
          setIsRed(self.nodes[self.nodes[keyParent].parent], true);
          key = self.nodes[keyParent].parent;
        } else {
          if (key == self.nodes[keyParent].right) {
            key = keyParent;
            rotateLeft(self, key);
          }
          keyParent = self.nodes[key].parent;
          setIsRed(self.nodes[keyParent], false);
          setIsRed(self.nodes[self.nodes[keyParent].parent], true);
          rotateRight(self, self.nodes[keyParent].parent);
        }
      } else {
        cursor = self.nodes[self.nodes[keyParent].parent].left;
        if (isRed(self.nodes[cursor])) {
          setIsRed(self.nodes[keyParent], false);
          setIsRed(self.nodes[cursor], false);
          setIsRed(self.nodes[self.nodes[keyParent].parent], true);
          key = self.nodes[keyParent].parent;
        } else {
          if (key == self.nodes[keyParent].left) {
            key = keyParent;
            rotateRight(self, key);
          }
          keyParent = self.nodes[key].parent;
          setIsRed(self.nodes[keyParent], false);
          setIsRed(self.nodes[self.nodes[keyParent].parent], true);
          rotateLeft(self, self.nodes[keyParent].parent);
        }
      }
    }
    setIsRed(self.nodes[self.root], false);
  }

  function replaceParent(Tree storage self, uint72 a, uint72 b) private {
    uint72 bParent = self.nodes[b].parent;
    self.nodes[a].parent = bParent;
    if (bParent == EMPTY) {
      self.root = a;
    } else {
      if (b == self.nodes[bParent].left) {
        self.nodes[bParent].left = a;
      } else {
        self.nodes[bParent].right = a;
      }
    }
  }

  function removeFixup(Tree storage self, uint72 key) private {
    uint72 cursor;
    while (key != self.root && !isRed(self.nodes[key])) {
      uint72 keyParent = self.nodes[key].parent;
      if (key == self.nodes[keyParent].left) {
        cursor = self.nodes[keyParent].right;
        if (isRed(self.nodes[cursor])) {
          setIsRed(self.nodes[cursor], false);
          setIsRed(self.nodes[keyParent], true);
          rotateLeft(self, keyParent);
          cursor = self.nodes[keyParent].right;
        }
        if (!isRed(self.nodes[self.nodes[cursor].left]) && !isRed(self.nodes[self.nodes[cursor].right])) {
          setIsRed(self.nodes[cursor], true);
          key = keyParent;
        } else {
          if (!isRed(self.nodes[self.nodes[cursor].right])) {
            setIsRed(self.nodes[self.nodes[cursor].left], false);
            setIsRed(self.nodes[cursor], true);
            rotateRight(self, cursor);
            cursor = self.nodes[keyParent].right;
          }
          setIsRed(self.nodes[cursor], isRed(self.nodes[keyParent]));
          setIsRed(self.nodes[keyParent], false);
          setIsRed(self.nodes[self.nodes[cursor].right], false);
          rotateLeft(self, keyParent);
          key = self.root;
        }
      } else {
        cursor = self.nodes[keyParent].left;
        if (isRed(self.nodes[cursor])) {
          setIsRed(self.nodes[cursor], false);
          setIsRed(self.nodes[keyParent], true);
          rotateRight(self, keyParent);
          cursor = self.nodes[keyParent].left;
        }
        if (!isRed(self.nodes[self.nodes[cursor].right]) && !isRed(self.nodes[self.nodes[cursor].left])) {
          setIsRed(self.nodes[cursor], true);
          key = keyParent;
        } else {
          if (!isRed(self.nodes[self.nodes[cursor].left])) {
            setIsRed(self.nodes[self.nodes[cursor].right], false);
            setIsRed(self.nodes[cursor], true);
            rotateLeft(self, cursor);
            cursor = self.nodes[keyParent].left;
          }
          setIsRed(self.nodes[cursor], isRed(self.nodes[keyParent]));
          setIsRed(self.nodes[keyParent], false);
          setIsRed(self.nodes[self.nodes[cursor].left], false);
          rotateRight(self, keyParent);
          key = self.root;
        }
      }
    }
    setIsRed(self.nodes[key], false);
  }
}
// ----------------------------------------------------------------------------
// End - BokkyPooBah's Red-Black Tree Library
// ----------------------------------------------------------------------------
