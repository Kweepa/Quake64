# Todo

- [ ] Nailgun shots
- [ ] Grenade projectile
- [ ] More optimization for the grenade FX — only simulate 1/4 of the particles and use flips to fill out the other 3/4. Keep the sin and cos components of each for rotation, like the rooms and items do, to reduce rotation costs.
- [ ] Ogre behaviour
- [ ] Knight behaviour
- [ ] Shambler behaviour
- [ ] Scrag behaviour (flying)
- [ ] Proper map complete screen/message (without going overboard)
- [ ] Decide what to do when you die in the game
- [ ] Player grenade launcher should launch grenade projectile
- [ ] Something unique for Chthon — ability to create a larger wireframe character like the items, with arbitrary lines? Maybe do this for all creatures, starting with what we have. To add a vert, immediately bind it to get its position. Vert names are probably not important now except for finding verts to use in the game; that could be done by tagging them. Would only need a jaw and a weapon end.
- [ ] When producing splat on the center of the screen, the sprite setup delays the screen flip by a raster line. Move the flip earlier so it doesn't have this problem. We can debug this by changing the border colour first thing and seeing where it is happening, so we can tweak its movement.
- [ ] Fix shotgun damage vs range. It's too easy to kill someone at a distance.
- [x] Remember to save item selection and camera position for the items tab.
- [ ] An arrow showing which way is forward in the items viewport.
- [x] Get rid of the static bitmap at a distance optimization. It doesn't look good and it's not optimizing for the worst case anyway.
- [ ] Fill the IRQ trampoline hole at $0903–$093E (~60 bytes of NOPs after `jmp start` at $0900). Park some small unaligned table or constants there so that padding isn’t wasted; trampoline at $093F must stay.
