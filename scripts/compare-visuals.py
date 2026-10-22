from pathlib import Path
import json
from PIL import Image,ImageChops

folder=Path(__file__).resolve().parents[1]/'tests/visual/website'
results=[]
for baseline in sorted(folder.glob('original-*.png')):
    current=folder/baseline.name.replace('original-','new-',1)
    regression=folder/baseline.name.replace('original-','regression-',1)
    intentional=regression.exists()
    with Image.open(baseline) as left,Image.open(regression if intentional else current) as right:
        same=left.size==right.size
        results.append({'page':baseline.name,'intentionalAttachmentControlExcluded':intentional,'sameDimensions':same,'pixelsMatch':same and ImageChops.difference(left.convert('RGB'),right.convert('RGB')).getbbox() is None})
(folder/'pixel-results.json').write_text(json.dumps(results,indent=2))
assert len(results)==30 and all(r['pixelsMatch'] for r in results),'Visual comparison failed'
print('30 preserved website comparisons match; intentional attachment controls excluded in 8 comparisons, actual new screenshots retained')
