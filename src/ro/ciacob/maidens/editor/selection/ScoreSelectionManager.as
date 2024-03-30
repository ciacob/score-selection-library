package ro.ciacob.maidens.editor.selection {
import flash.events.Event;
import flash.events.EventDispatcher;

import ro.ciacob.desktop.data.DataElement;
import ro.ciacob.maidens.legacy.ModelUtils;
import ro.ciacob.maidens.legacy.ProjectData;
import ro.ciacob.maidens.legacy.constants.DataFields;
import ro.ciacob.utils.Descriptor;

public class ScoreSelectionManager extends EventDispatcher {
    public function ScoreSelectionManager() {
        _selectedElements = [];
        _selectionStack = [];
    }

    public static const SELECTION_CHANGED:String = 'selectionChanged';

    public static const MODE_REPLACE:String = 'modeReplace';
    public static const MODE_RANGE:String = 'modeRange';
    public static const MODE_SELF:String = 'modeSelf';

    private static const ACTION_ADD:String = 'actionAdd';
    private static const ACTION_REMOVE:String = 'actionRemove';
    private static const ACTION_INVERT:String = 'actionInvert';

    /**
     * Storage for the element that acts as a selection anchor. If selection is unique
     * (i.e., not "multiple"), then `_selectionAnchor` will also contain the one and only
     * selected element.
     */
    private var _selectionAnchor:DataElement;

    /**
     * Storage for all selected elements, including the anchor.
     */
    private var _selectedElements:Array;

    /**
     * Detached, shallow clone of `_selectedElements`, recreated on each call to `modifySelection()`.
     * Its aim is to prevent accidental (and, potentially, semantically-faulty) changes from being directly
     * made to the low-level stack of selected elements.
     */
    private var _selectionStack:Array;

    /**
     * Legacy. Returns the `selectionAnchor`, also "the" selected element, if a unique
     * selection model is desired (or appropriate).
     */
    public function get selectionAnchor():DataElement {
        return _selectionAnchor;
    }

    /**
     * Possibly empty Array including all currently selected elements.
     * NOTE: This is a detached, shallow copy. Element instances it contains are genuine, and can be worked
     * upon, but the very structure and content of the selection cannot be altered by modifying the returned
     * Array. Instead, one must use the `clearSelection`, `addToSelection`, `removeFromSelection` and/or
     * `invertSelection` methods, as needed.
     */
    public function get selectionStack():Array {
        return _selectionStack;
    }

    /**
     * Legacy. Sets the `selectionAnchor`, also "the" selected element, if a unique
     * selection model is desired (or appropriate).
     */
    public function set selectionAnchor(value:DataElement):void {
        if (value != _selectionAnchor) {
            _selectionAnchor = _modifySelection([value], ACTION_ADD, MODE_REPLACE);
            dispatchEvent(new Event(SELECTION_CHANGED));
        }
    }

    /**
     * Adds to existing selection.
     * @param   stack
     *          The stack to be added, made of one or more ProjectData instances.
     *
     * @param   mode
     *          How to treat provided stack in relation to existing selection, if any.
     *          Available options are all the publicly available `MODE...` constants,
     *          namely:
     *          - MODE_REPLACE: default; existing selection will be discarded in favor of new one.
     *
     *          - MODE_RANGE: asserts that [1] `stack` only contains one element, and [2] there is
     *            a non-null `_selectionAnchor`; establishes a dense (i.e. no gaps) range between the
     *            existing `_selectionAnchor` and that one element, and adds the result to the selection,
     *            (conserving the `_selectionAnchor`). Failure of any of the assertions will effectively
     *            transpose this to another, more appropriate mode.
     *
     *          - MODE_SELF: only adds given elements in the `stack` to the selection. In this case, the
     *            `stack` Array can be sparse (but it must be normalized, i.e., contain elements of same
     *             type).
     */
    public function addToSelection(stack:Array, mode:String = null):void {
        _selectionAnchor = _modifySelection(stack, ACTION_ADD, mode);
    }

    /**
     * Removes from existing selection.
     *
     * @param   stack
     *          Element(s) to be removed from the current selection (if found).
     *
     * @param   mode
     *          How to treat provided stack in relation to existing selection, if any.
     *          Available options are a subset of the publicly available `MODE...` constants,
     *          namely:
     *         - MODE_RANGE: asserts that [1] `stack` only contains one element, and [2] there is
     *            a non-null `_selectionAnchor`; establishes a dense (i.e. no gaps) range between the
     *            existing `_selectionAnchor` and that one element, and removes the elements within this
     *            range from the selection, while conserving the `_selectionAnchor` (which cannot be
     *            removed this way). Failure of any of the assertions will effectively
     *            transpose this to another, more appropriate mode.
     *
     *          - MODE_SELF: default; only removes given elements (if found) from the selection. In this case,
     *            the `stack` Array can be sparse (but it must be normalized, i.e., contain elements of
     *            same type).
     */
    public function removeFromSelection(stack:Array, mode:String = null):void {
        _selectionAnchor = _modifySelection(stack, ACTION_REMOVE, mode);
    }

    /**
     * Removes everything from the selection (including the _selectionAnchor).
     */
    public function clearSelection():void {
        _selectionAnchor = _modifySelection(null);
    }

    /**
     * Creates a (sparse) range from the extremities of the current selection, and removes all range elements
     * currently _in_ the selection, while adding all those that _were_not_ in the selection. Only makes sense
     * when the current selection is already sparse.
     */
    public function invertSelection():void {
        _selectionAnchor = _modifySelection(null, ACTION_INVERT, null);
    }

    /**
     *
     * @param payload
     * @param action
     * @param mode
     * @return  The element, within the selection stack, to be considered the "selection anchor", the pivot
     *          based on which all range operations are carried out, or the "unique selection", if this model
     *          is employed.
     */
    private function _modifySelection(payload:Array, action:String = null, mode:String = null):DataElement {

        // 1. No payload means clearing the current selection; implied: ACTION_ADD, MODE_REPLACE.
        if (!payload || payload.length == 0 || (payload.length == 1 && !payload[0])) {
            _selectedElements.length = 0;
            _selectionStack.length = 0;
            return null;
        }

        // 2. Single element payload with MODE_REPLACE renders `action` futile.
        if (payload.length == 1 && mode == MODE_REPLACE) {
            _selectedElements.length = 0;
            _selectedElements[0] = payload[0];
            _selectionStack = _selectedElements.concat();
            return _selectedElements[0];
        }

        // 3. Single element with MODE_RANGE or MODE_SELF can pair with all action types: ACTION_ADD, ACTION_REMOVE,
        // or ACTION_INVERT.
        if (payload.length == 1) {
            var selectedElement : DataElement = (payload[0] as DataElement);

            // Trying to add the current anchor makes no sense.
            if (selectedElement == _selectionAnchor && action == ACTION_ADD) {
                return _selectionAnchor;
            }

            // From this point onward, we need to work on normalized selection lists, i.e., all the elements in the
            // selection must be of the same type. We achieve this by resolving to the lowest hierarchical type available
            // across the entire list.
            // NOTE: `_normalizeSelection()` changes given Array in place, and returns an Array with normalized
            // old and new anchor elements.
            var anchors : Array = _normalizeSelection (_selectedElements, _selectionAnchor, selectedElement);
            var normOldAnchor : DataElement = (anchors[0] as DataElement);
            var normNewAnchor : DataElement = (anchors[1] as DataElement);

            // Normalizing can sometimes uncover situations that make no sense as well.
            if (normOldAnchor == normNewAnchor) {
                return _selectionAnchor;
            }

            // Handle the six possible combinations for a single element payload. In MODE_RANGE it is simpler, because
            // we delegate all the actual management (adding or removing elements) to the `_buildRange()` method.
            var matchIndex : int;
            switch (mode) {
                case MODE_RANGE:
                    var range : Array = _buildRange (_selectedElements, normOldAnchor, normNewAnchor, action);
                    _selectedElements.length = 0;
                    Array.prototype.push.apply(_selectedElements, range.splice(0, range.length));
                    return normNewAnchor;

                case MODE_SELF:
                    switch (action) {
                        case ACTION_ADD:
                            _selectedElements.push (normNewAnchor);
                            return normNewAnchor;

                        case ACTION_REMOVE:
                            matchIndex = _selectedElements.indexOf(normNewAnchor);
                            if (matchIndex != -1) {
                                _selectedElements.splice (matchIndex, 1);
                            }
                            return normOldAnchor;

                        case ACTION_INVERT:
                            matchIndex = _selectedElements.indexOf(normNewAnchor);
                            if (matchIndex == -1) {
                                _selectedElements.push (normNewAnchor);
                                return normNewAnchor;
                            }
                            _selectedElements.splice (matchIndex, 1);
                            return normOldAnchor;
                    }
            }
        }

        // If we reach down here, our payload contains more than one element. This will only be the case when this
        // class is programmatically manipulated (e.g., in order to instate a very specific selection state - the kind
        // of things macros or generators are likely to do).
        // TODO: support multiple elements payload.

        // We must return an explicit value or the class will not compile.
        return null;
    }

    /**
     * Determines whether given `str1` is a case-sensitive prefix of `str2`.
     * @param   str1
     *          The prefix to search.
     *
     * @param   str2
     *          The string to search into.
     *
     * @return  `True` in case of a match, `false` otherwise.
     */
    private static function _isPrefix(str1:String, str2:String):Boolean {
        return str2.indexOf(str1) === 0;
    }

    /**
     * Finds the longest common prefix of two strings and optionally removes a trailing character.
     *
     * @param str1 The first input string.
     * @param str2 The second input string.
     * @param cutOffChar (Optional) The character to cut off if found trailing in the common prefix.
     * @return The longest common prefix of the two input strings, with optional trailing character removed.
     */
    private static function _getLongestCommonPrefix(str1:String, str2:String, cutOffChar:String = ''):String {
        var prefix:String = '';
        const minLength:int = Math.min(str1.length, str2.length);
        for (var i:int = 0; i < minLength; i++) {
            if (str1.charAt(i) === str2.charAt(i)) {
                prefix += str1.charAt(i);
            } else {
                break;
            }
        }
        if (cutOffChar != '' && prefix != '') {
            var lastChar:String = prefix.charAt(prefix.length - 1);
            if (lastChar == cutOffChar) {
                prefix = prefix.substr(0, prefix.length - 1);
            }
        }
        return prefix;
    }

    /**
     * Resolves given `anchor` DataElement to one of the elements of given `routes`. This could be the very `anchor`
     * itself, if present there, or one of its children (if one can be located).
     *
     * @param   anchor
     *          DataElement instance to look-up within given `routes`.
     *
     * @param   routes
     *          Array of DataElement instances, potentially containing `anchor` itself, or one of its children.
     *
     * @return  The given `anchor`, if found in given `routes`, or one of its children, otherwise. If `routes` was
     *          properly build, this method should never return `null`.
     */
    private static function _resolveRawAnchor (anchor : DataElement, routes : Array) : DataElement {
        if (!anchor) {
            return null;
        }

        // If not null, given anchor is expected to exist within given `routes` either as such, or
        // virtually, by means of at least one of its children. If the later, than the first available
        // child will become the new anchor.
        var anchorRoute : String = anchor.route;
        if (routes.indexOf(anchorRoute) != -1) {
            return anchor;
        }
        var elementsMap : Object= anchor.parentFlatElementsMap;
        for (var i : int = 0; i < routes.length; i++) {
            if (_isPrefix(anchorRoute, routes[i] as String)) {
                return (elementsMap[routes[i]] as DataElement);
            }
        }

        // Shouldn't reach here, but code won't compile without an explicit return.
        return null;
    }

    /**
     * Modifies in-place the given `rawSelection` Array, so that (1) all its elements are DataElement instances of the
     * same hierarchical level, (2) there are no duplicates, and (3) parents consume their children, if found.
     *
     * @param   rawSelection
     *          An Array of selected DataElement instances, as originally provided by the client code.
     *
     * @param   existingAnchor
     *          Optional. If provided, represents the selection element that acted as a selection's pivot or anchor
     *          BEFORE the current session (e.g., the object the user previously had selected). When selection is
     *          provided programmatically, rather than by a human user, this argument can be `null`.
     *
     * @param   proposedAnchor
     *          Optional. If provided, represents the selection element that will act as a selection's pivot or anchor
     *          STARTING WITH te current session (e.g., the object the user has just selected). When selection is
     *          provided programmatically, rather than by a human user, this argument can be `null`.
     *
     * @return  Returns, as a side-effect, an Array with the given `existingAnchor` and `proposedAnchor`, which might
     *          have been left untouched or changed to reflect the normalization operation (e.g., on, or both, of the
     *          anchors could have been substituted by one of their respective children, if applicable).
     */
    private static function _normalizeSelection (rawSelection : Array, existingAnchor : DataElement = null,
                                          proposedAnchor : DataElement = null) : Array {

        // Hierarchically sort the stack, putting parents first
        var i: int;
        var flatElementsMap : Object = (rawSelection[0] as DataElement).parentFlatElementsMap;
        var routes : Array = [];
        for (i = 0; i < rawSelection.length; i++) {
            routes[i] = (rawSelection[i] as DataElement).route;
        }
        if (existingAnchor) {
            routes.push (existingAnchor.route);
        }
        if (proposedAnchor) {
            routes.push (proposedAnchor.route);
        }
        routes.sort (Descriptor.multiPartComparison);

        // Get a hold of a lowest hierarchical level across the entire stack.
        var lowestLevelSample : DataElement = (flatElementsMap[routes[routes.length - 1]] as DataElement);
        var lowestLevelType : String = (lowestLevelSample.getContent(DataFields.DATA_TYPE) as String);

        // Trim (or "prune") the stack, removing children of parents that are also in the stack
        for (i = routes.length - 1; i > 0; i--) {
            if (_isPrefix(routes[i - 1], routes[i]) || (routes[i - 1] == routes[i])) {
                routes.splice(i, 1);
            }
        }

        // "Explode" the parents to their equivalent children of the hierarchical level noted at #1
        rawSelection.length = 0;
        for (i = 0; i < routes.length; i++) {
            var element : DataElement = (flatElementsMap[routes[i]] as DataElement);
            var elType : String = element.getContent(DataFields.DATA_TYPE);
            if (elType == lowestLevelType) {
                rawSelection.push (element);
            } else {
                Array.prototype.push.apply(rawSelection,  ModelUtils.getDescendantsOfType (
                        (element as ProjectData), lowestLevelType));
            }
        }

        // Realign `existingAnchor` and `proposedAnchor`, if given, with the new content of the selection stack.
        existingAnchor = _resolveRawAnchor (existingAnchor, routes);
        proposedAnchor = _resolveRawAnchor (proposedAnchor, routes);
        return [existingAnchor, proposedAnchor];
    }

    /**
     * Builds a dense range of DataElement instances, from `startElement` up to `endElement` and applies it on top of
     * an `existingSelection` via one of three possible workflows: addition, subtraction or inversion.
     *
     * @param   existingSelection
     *          Array defining a "reference" selection to act upon.
     *
     * @param   startElement
     *          An element (DataElement instance) to start building a range from.
     *
     * @param   endElement
     *          An element (DataElement instance) to stop building a range at.
     *
     * @param   actionType
     *          A String describing how to apply the built range onto the `existingSelection`. Accepted are the values
     *          of the ACTION_... constants, i.e., ACTION_ADD, ACTION_REMOVE and ACTION_INVERT.
     * @return
     */
    private static function _buildRange (existingSelection : Array, startElement : DataElement, endElement : DataElement,
                                  actionType : String) : Array {
        if (!startElement || !endElement) {
            return existingSelection;
        }

        // Make sure `startElement` and `endElement` are true to their natural order, i.e., `startElement` "comes
        // before" `endElement` in the hierarchy.
        var tmp : Array = [startElement, endElement];
        tmp.sort (Descriptor.multiPartComparison);
        startElement = (tmp[0] as DataElement);
        endElement = (tmp[1] as DataElement);

        // Get the common ancestor of the two elements.
        var flatElementsMap : Object = startElement.parentFlatElementsMap;
        var ancestorRoute : String = _getLongestCommonPrefix (startElement.route, endElement.route);
        if (!ancestorRoute) {
            return existingSelection;
        }
        var ancestor : DataElement = (flatElementsMap[ancestorRoute] as DataElement);
        if (!ancestor) {
            return existingSelection;
        }

        // Request from the common ancestor all descendants of the same type as `startElement` and `endElement`, and
        // trim the resulting range.
        var elType : String = startElement.getContent(DataFields.DATA_TYPE) as String;
        var descendants : Array = ModelUtils.getDescendantsOfType(ancestor as ProjectData, elType);
        if (!descendants.length) {
            return existingSelection;
        }
        descendants = descendants.slice (descendants.indexOf(startElement), descendants.indexOf(endElement) + 1);

        // Decide how to apply obtained range to `existingSelection`, based on the given `actionType`.
        var i : int;
        var matchIndex : int;
        switch (actionType) {

            // ACTION_ADD: add elements from `descendants` to `existingSelection`, provided they're not there already;
            // sort everything in natural order.
            case ACTION_ADD:
                for (i = 0; i < descendants.length; i++) {
                    if (existingSelection.indexOf(descendants[i]) == -1) {
                        existingSelection.push (descendants[i]);
                    }
                }
                existingSelection.sort (Descriptor.multiPartComparison);
                break;

            // ACTION_REMOVE: remove from `existingSelection` those elements that also exist in `descendants`;
            case ACTION_REMOVE:
                for (i = 0; i < descendants.length; i++) {
                    matchIndex = existingSelection.indexOf(descendants[i]);
                    if (matchIndex != -1) {
                        existingSelection.splice (matchIndex, 1);
                    }
                }
                break;

            // ACTION_INVERT: proceed as for ACTION_REMOVE, but also remove the matches from `descendants`; then add to
            // `existingSelection` anything that might have remained in `descendants`; sort everything in natural order.
            case ACTION_INVERT:
                for (i = descendants.length - 1; i > 0; i--) {
                    matchIndex = existingSelection.indexOf(descendants[i]);
                    if (matchIndex != -1) {
                        existingSelection.splice (matchIndex, 1);
                        descendants.splice (i, 1);
                    }
                }
                if (descendants.length) {
                    Array.prototype.push.apply(existingSelection, descendants);
                }
                existingSelection.sort (Descriptor.multiPartComparison);
                break;
        }

        return existingSelection;
    }
}
}
