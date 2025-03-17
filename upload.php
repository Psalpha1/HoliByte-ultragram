<?php
// Directory where images will be uploaded
$uploadDirectory = 'users_profiles_images/';

// Ensure the upload directory exists, if not create it
if (!file_exists($uploadDirectory)) {
    mkdir($uploadDirectory, 0777, true);
}

// Check if a file is uploaded
if (isset($_FILES['file'])) {
    $file = $_FILES['file'];

    // Validate file type (only image files allowed)
    $allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/jpg'];
    if (!in_array($file['type'], $allowedTypes)) {
        echo json_encode(['error' => 'Invalid file type. Only JPEG, PNG, or GIF or jpg are allowed.']);
        exit;
    }

    // Validate file size (maximum 5MB)
    if ($file['size'] > 5 * 1024 * 1024) {
        echo json_encode(['error' => 'File size exceeds the 5MB limit.']);
        exit;
    }

    // Generate a unique file name
    $fileExtension = pathinfo($file['name'], PATHINFO_EXTENSION);
    $fileName = uniqid() . '.' . $fileExtension;

    // Move the uploaded file to the server's upload directory
    $uploadPath = $uploadDirectory . $fileName;
    if (move_uploaded_file($file['tmp_name'], $uploadPath)) {
        // Return the URL of the uploaded image
        $imageUrl = 'http://' . $_SERVER['HTTP_HOST'] . '/' . $uploadPath;
        echo json_encode(['url' => $imageUrl]);
    } else {
        echo json_encode(['error' => 'File upload failed.']);
    }
} else {
    echo json_encode(['error' => 'No file uploaded.']);
}
?>
