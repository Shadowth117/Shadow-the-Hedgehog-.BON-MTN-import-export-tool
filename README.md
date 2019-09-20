***NOTE FOR BOTH TOOLS YOU MUST IMPORT, EXPORT, AND REIMPORT THE MODEL FOR THESE TO WORK PROPERLY DUE TO INITIAL IMPORT REORDERING***

The first script here is a script I made to import and export the extra attributes of .BON files in Shadow the Hedgehog to 3ds Max onto .DFF imports made AAP's RWIO: https://gtaforums.com/topic/838479-dff-importer-and-exporter-for-3ds-max/

Basically, Renderware strips a lot of information from models and so Sega decided to include extra information, such individual bone names, onto a copy of the bone structure with some variables for various uses. I wrote this primarily to make rerigging and exporting cleaner.

The second script exports animations from and can attempt (poorly) to import them to max. Unfortunately, the nature of the animations makes them difficult to accurately bring into the program. However, exports work very well. At the moment however, exports REQUIRE that the user hex edits the animation id (The 4 bytes at 0x10) from the original animation into the new file. I may come up with a better way of doing this, but these values are arbitrary and cannot simply be calculated. 

Other than that, for best results, use 'Set Key" at the beginning and end of the animation on all bones for best results. Animations in testing appeared to export as intended, but be aware that there may be unforeseen issues. Also note that animations in Shadow are 60 fps so the scene framerate should be set as such for export. 

Currently, this tool is the only way to extract and repack the MTP animation archives: https://github.com/Sewer56/ShadowMTP although loose MTN files do exist. 

In addition, I've included my tag tool for shadow and heroes in case it can be of use.
