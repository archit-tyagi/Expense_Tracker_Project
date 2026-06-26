window.onload = function() {

    window.ui = SwaggerUIBundle({
        urls: [
            {
                url: "openapi/auth-service.json",
                name: "Authentication Service"
            },
            {
                url: "openapi/user-service.json",
                name: "User Service"
            },
            {
                url: "openapi/message-service.json",
                name: "Message Service"
            },
            {
                url: "openapi/expense-service.json",
                name: "Expense Service"
            }
        ],

        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [
            SwaggerUIBundle.presets.apis,
            SwaggerUIStandalonePreset
        ],
        plugins: [
            SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "StandaloneLayout"
    });
};