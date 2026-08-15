Enemies will all be 12 verts/12 lines with exactly the same skeleton layout, just different proportions and poses.
There will be 24 animation frames, and 2 rotations.
We're going to pre rotate and store the enemies at 45 degrees so that we don't pay the rotation cost - just use unique routines for coord flips and sign changes for the other 6 rotations.
So that's 24x2x12x3 per enemy ~ 2Kb, and one line layout.

Animation frames are defined in local space, with signed byte offsets from the base of the creature.

The animation frames will be:
Idle 2
Alert 2
Walk 4
AttackA 4 (maybe melee)
AttackB 4 (maybe ranged)
AttackC 4 (whatever suits)
Flinch 1
Death 3

Each level will have 3 enemy types selected from Grunt, Knight, Rottweiler, Scrag, Ogre, Shambler, Chthon.
