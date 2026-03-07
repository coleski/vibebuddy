# Queued Dictation Feature Requirements

## Overview
Implement a queued dictation system that allows users to start a new recording while a previous transcription is still processing. Multiple transcriptions should be processed sequentially and results should be pasted/typed in the order they were recorded.

## Core Features

### 1. Queue Management
- Support multiple simultaneous recordings in queue
- Process transcriptions sequentially (FIFO)
- Maintain recording order for paste operations
- Clean up temporary audio files after processing
- Handle queue state management (processing/idle)

### 2. Recording System Changes
- Remove transcription cancellation when hotkey pressed during processing
- Allow new recordings to start while transcription is in progress
- Generate unique timestamped filenames to prevent file conflicts
- Track recording state to prevent concurrent recordings

### 3. UI Indicators
- Display multiple orbs side-by-side for concurrent states
- Show recording orb for active recording
- Show transcribing orb(s) for items being processed
- Visual feedback for queue depth

### 4. Transcription Processing
- Sequential processing of queued items
- Maintain transcription settings per queue item (model, language, AI mode)
- Proper error handling for individual queue items
- Continue processing remaining items if one fails

### 5. Paste/Typing System
- Sequential paste operations for completed transcriptions
- Support both clipboard paste and simulated typing modes
- Queue-aware paste system to prevent conflicts
- Proper timing between paste operations
- Maintain user's clipboard state when appropriate

### 6. State Management
- Track multiple transcription states simultaneously
- Maintain queue of pending transcriptions
- Process completion tracking
- Error state handling per queue item

## Technical Requirements

### 1. Data Models
- QueuedTranscription model with unique IDs
- Audio URL tracking for temporary files
- Timestamp and duration tracking
- Settings preservation per item (AI mode, model, language)

### 2. Action System
- Queue-specific actions (queueTranscription, startProcessingQueue)
- Result handling actions (transcriptionQueueResult, transcriptionQueueError)
- Clear separation from single transcription flow

### 3. Effect Management
- Cancellable effects for queue processing
- Concurrent effect handling for multiple operations
- Proper cleanup effects for temporary files

### 4. File Management
- Unique filename generation to prevent collisions
- Temporary file cleanup after processing
- History storage for completed transcriptions (if enabled)

### 5. Audio System
- Prevent concurrent recordings
- Proper recording state management
- Audio file URL tracking and cleanup

### 6. Paste Client Updates
- Actor-based concurrent paste handling
- Internal paste queue for sequential operations
- Comprehensive logging for debugging
- Proper settings handling in actor context

## Error Handling

### 1. Recording Errors
- Handle recording failures gracefully
- Continue with other queue items
- User feedback for failed recordings

### 2. Transcription Errors
- Individual item error handling
- Queue processing continuation
- Error reporting without stopping queue

### 3. Paste Errors
- Retry mechanisms for paste failures
- Fallback to clipboard retention
- User notification of paste issues

### 4. File System Errors
- Handle file conflicts
- Cleanup failed operations
- Prevent file system leaks

## User Experience

### 1. Hotkey Behavior
- Press hotkey to start recording
- Press again while transcribing to queue another recording
- No cancellation of in-progress transcriptions
- Support both press-and-hold and double-tap modes

### 2. Visual Feedback
- Clear indication of queue state
- Progress feedback for each item
- Error state visualization

### 3. Audio Feedback
- Appropriate sound effects for each state
- Queue-aware audio cues

## Performance Considerations

### 1. Memory Management
- Efficient queue operations
- Proper cleanup of completed items
- Audio file management

### 2. Concurrent Operations
- Safe concurrent transcription processing
- Thread-safe state updates
- Actor isolation for paste operations

### 3. Resource Usage
- Limit maximum queue size if needed
- Efficient audio file handling
- Proper cleanup of temporary resources

## Testing Requirements

### 1. Basic Queue Operations
- Single item processing
- Multiple item queuing
- Sequential processing verification

### 2. Error Scenarios
- Recording failures
- Transcription errors
- Paste system failures
- File system issues

### 3. Concurrency Testing
- Rapid successive recordings
- Stress testing with multiple items
- Race condition verification

### 4. Integration Testing
- Full end-to-end queue processing
- Settings preservation across queue items
- Cleanup verification

## Implementation Status
- ✅ Core queue data models
- ✅ Basic queue processing logic  
- ✅ UI updates for multiple orbs
- ✅ File conflict resolution
- ❌ Paste system reliability (current issue)
- ❌ Comprehensive error handling
- ❌ Performance optimization
- ❌ Full testing coverage

## Known Issues
1. Paste operations not executing despite successful transcription
2. Action dispatch between transcription completion and paste handling
3. Need better debugging and logging for paste flow
4. Potential race conditions in queue state management

## Next Steps
1. Debug and fix paste system reliability
2. Add comprehensive logging throughout the flow
3. Implement proper error handling for all scenarios
4. Add performance monitoring and optimization
5. Create comprehensive test suite