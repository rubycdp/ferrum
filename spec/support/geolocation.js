navigator.geolocation.getCurrentPosition = function(success, failure) {
    success({ coords: {
        latitude: 1,
        longitude: -1,
    }, timestamp: Date.now() });
}
