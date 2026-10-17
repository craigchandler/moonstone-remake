extends RefCounted

static func select(weights: Array, elapsed: int, duration: int) -> int:
    var total: int = 0
    for weight in weights:
        total += int(weight)
    var position: int = mini(int(float(clampi(elapsed, 0, duration - 1)) * total / duration), total - 1)
    for i in range(weights.size()):
        if position < int(weights[i]):
            return i
        position -= int(weights[i])
    return weights.size() - 1
