import strutils

proc displayFixedWidthText(text: string, width: int, offset: int) =
  var formattedText = ""
  var visibleText = ""
  for line in text.splitLines:
    var currentOffset = 0
    let lineLen = line.len
    if currentOffset + lineLen <= offset:
      currentOffset += lineLen + 1  # Add 1 for newline character
    else:
      if currentOffset < offset:
        let startIndex = offset - currentOffset
        visibleText.add(line[startIndex..^1])  # Append the remaining part of the line
        currentOffset = offset
      else:
        visibleText.add(line)
        currentOffset += lineLen + 1  # Add 1 for newline character
      if visibleText.len >= width:
        formattedText.add(visibleText[0..width-1])  # Trim to fit within width
        formattedText.add("\n")
        visibleText = ""
  if visibleText.len > 0:
    formattedText.add(visibleText[0..^1])  # Trim trailing newline
  echo formattedText

# Example usage with longer text and complex content
let text = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Proin eget ullamcorper orci. Aliquam erat volutpat.
Donec non venenatis neque. Phasellus cursus sapien sit amet orci sagittis, at posuere nunc ultricies. Mauris
ornare sapien vel nisl tincidunt, ac malesuada mi bibendum. Curabitur nec est sed tellus posuere cursus vitae
velit nec. Fusce nec lobortis arcu. Vivamus auctor turpis ac tempor venenatis. Duis ultricies nisl at nisi
fringilla sodales. Aliquam id lorem non magna aliquet eleifend. Suspendisse aliquet purus id sapien ullamcorper,
nec efficitur purus lobortis. Ut a mauris ut orci venenatis convallis vel ac odio. Vestibulum aliquam neque vel
dui condimentum commodo. Sed efficitur ultricies enim, non tristique dolor ultricies quis. Vivamus eget arcu ac
sapien consectetur ullamcorper. Etiam sodales, urna nec congue venenatis, est mi aliquam libero, a elementum
dolor tortor ut felis. Cras dictum mauris nunc, nec tincidunt dui ultrices nec. Integer tristique sem eu nulla
sodales efficitur. Nullam vitae rutrum nisl. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices
posuere cubilia curae; In hac habitasse platea dictumst. Donec eget efficitur ligula. Ut tincidunt, est eget
dapibus fringilla, nisl metus suscipit eros, at efficitur dui magna at nibh. Nunc eu purus vitae lacus semper
congue. Nulla lobortis dapibus vestibulum. Proin ultricies vitae dolor et eleifend. Nulla et efficitur nisl.
Pellentesque posuere nisl in justo mollis, nec convallis eros hendrerit. Curabitur ultricies, arcu sed euismod
pulvinar, orci lacus feugiat lectus, nec finibus quam arcu vitae ante. Mauris lacinia varius justo, ut faucibus
dolor mattis ac. Suspendisse id lectus sed neque elementum efficitur nec vel erat. Ut laoreet interdum leo, nec
efficitur libero congue non. Nullam id libero sit amet urna maximus venenatis nec vitae ipsum. Nam et quam urna.
"""

let width = 50
let offset = 5  # Adjust this offset to scroll left and right

displayFixedWidthText(text, width, offset)

